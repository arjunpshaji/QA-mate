export interface Env {
	RECORDING_META: KVNamespace;
	screen_recordings: R2Bucket;
}

interface RecordingMetadata {
	id: string;
	status: "pending" | "ready" | "error";
	createdAt: string;
	expiresAt?: string;
	videoSize?: number;
	thumbSize?: number;
	contentType?: string;
	title?: string;
	views?: number;
}

const CORS_HEADERS: Record<string, string> = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "GET, HEAD, POST, PUT, DELETE, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Content-Length, Range, Authorization, X-Requested-With",
	"Access-Control-Expose-Headers": "Content-Range, Content-Length, Accept-Ranges, Content-Type, ETag",
};

function jsonResponse(data: unknown, status = 200): Response {
	return new Response(JSON.stringify(data), {
		status,
		headers: {
			"Content-Type": "application/json",
			...CORS_HEADERS,
		},
	});
}

function generateId(length = 10): string {
	const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
	const array = new Uint8Array(length);
	crypto.getRandomValues(array);
	return Array.from(array, (byte) => chars[byte % chars.length]).join("");
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		const url = new URL(request.url);
		const origin = url.origin;
		const path = url.pathname;
		const method = request.method.toUpperCase();

		// Handle CORS Preflight
		if (method === "OPTIONS") {
			return new Response(null, {
				status: 204,
				headers: CORS_HEADERS,
			});
		}

		try {
			// Check if maintenance mode / service paused flag is set in KV
			const isPaused = (await env.RECORDING_META.get("CONFIG:PAUSED")) === "true";

			// Health check
			if ((path === "/" || path === "/health" || path === "/status") && method === "GET") {
				return jsonResponse({
					status: isPaused ? "maintenance" : "ok",
					service: "QA Mate Screen Recording Backend",
					version: "1.0.0",
					r2Bucket: "screen-recordings",
					paused: isPaused,
				}, isPaused ? 503 : 200);
			}

			// If paused, reject upload endpoints with 503
			if (isPaused && method === "POST") {
				return jsonResponse({
					error: "Cloud recording service is temporarily paused or at billing quota.",
					isServerDown: true,
					status: 503,
				}, 503);
			}

			// 1. Initialize Upload: POST /api/upload/init or POST /api/upload or POST /
			if ((path === "/api/upload/init" || path === "/api/upload" || path === "/upload") && method === "POST") {
				let body: any = {};
				try {
					body = await request.json();
				} catch {
					// Fallback to empty config if body not JSON
				}

				const uploadId = generateId(10);
				const now = new Date();
				const expiresAt = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString(); // 30 days default

				const meta: RecordingMetadata = {
					id: uploadId,
					status: "pending",
					createdAt: now.toISOString(),
					expiresAt,
					videoSize: body?.video?.fileSize,
					thumbSize: body?.thumbnail?.fileSize,
					contentType: body?.video?.contentType || "video/mp4",
					title: body?.title || `Recording ${now.toLocaleDateString()}`,
					views: 0,
				};

				await env.RECORDING_META.put(`meta:${uploadId}`, JSON.stringify(meta), {
					expirationTtl: 30 * 24 * 60 * 60, // 30 days
				});

				return jsonResponse({
					uploadId,
					videoUploadUrl: `${origin}/api/upload/${uploadId}/video`,
					thumbnailUploadUrl: `${origin}/api/upload/${uploadId}/thumbnail`,
					playerUrl: `${origin}/r/${uploadId}`,
					streamUrl: `${origin}/stream/${uploadId}`,
					thumbnailUrl: `${origin}/thumbnail/${uploadId}`,
					expiresAt,
				}, 201);
			}

			// 2. Upload Video Binary: PUT /api/upload/:id/video
			const videoUploadMatch = path.match(/^\/api\/upload\/([a-zA-Z0-9_-]+)\/video$/);
			if (videoUploadMatch && method === "PUT") {
				const uploadId = videoUploadMatch[1];
				const contentType = request.headers.get("content-type") || "video/mp4";

				if (!request.body) {
					return jsonResponse({ error: "Missing request body" }, 400);
				}

				// Stream video directly into R2
				await env.screen_recordings.put(`videos/${uploadId}.mp4`, request.body, {
					httpMetadata: {
						contentType,
					},
					customMetadata: {
						uploadId,
						uploadedAt: new Date().toISOString(),
					},
				});

				// Update metadata status in KV
				const existingRaw = await env.RECORDING_META.get(`meta:${uploadId}`);
				let meta: RecordingMetadata = existingRaw ? JSON.parse(existingRaw) : { id: uploadId, status: "pending", createdAt: new Date().toISOString() };
				meta.status = "ready";
				await env.RECORDING_META.put(`meta:${uploadId}`, JSON.stringify(meta));

				return jsonResponse({
					success: true,
					uploadId,
					playerUrl: `${origin}/r/${uploadId}`,
					streamUrl: `${origin}/stream/${uploadId}`,
				});
			}

			// 3. Upload Thumbnail Binary: PUT /api/upload/:id/thumbnail
			const thumbUploadMatch = path.match(/^\/api\/upload\/([a-zA-Z0-9_-]+)\/thumbnail$/);
			if (thumbUploadMatch && method === "PUT") {
				const uploadId = thumbUploadMatch[1];
				const contentType = request.headers.get("content-type") || "image/jpeg";

				if (!request.body) {
					return jsonResponse({ error: "Missing request body" }, 400);
				}

				await env.screen_recordings.put(`thumbnails/${uploadId}.jpg`, request.body, {
					httpMetadata: { contentType },
					customMetadata: { uploadId },
				});

				return jsonResponse({ success: true, uploadId });
			}

			// 4. Video Stream with HTTP Range Requests: GET /stream/:id (or /stream/:id.mp4)
			const streamMatch = path.match(/^\/stream\/([a-zA-Z0-9_-]+)(?:\.mp4)?$/);
			if (streamMatch && (method === "GET" || method === "HEAD")) {
				const uploadId = streamMatch[1];
				const rangeHeader = request.headers.get("range");

				const object = await env.screen_recordings.get(`videos/${uploadId}.mp4`, {
					range: rangeHeader ? request.headers : undefined,
					onlyIf: request.headers,
				});

				if (!object) {
					return new Response("Video recording not found", {
						status: 404,
						headers: CORS_HEADERS,
					});
				}

				const headers = new Headers();
				object.writeHttpMetadata(headers);
				headers.set("etag", object.httpEtag);
				headers.set("Accept-Ranges", "bytes");
				for (const [k, v] of Object.entries(CORS_HEADERS)) {
					headers.set(k, v);
				}
				headers.set("Cache-Control", "public, max-age=604800, immutable");

				// Handle 206 Partial Content if Range was requested
				if (rangeHeader && object.range) {
					const r = object.range as { offset?: number; length?: number };
					const start = r.offset ?? 0;
					const end = (r.offset ?? 0) + (r.length ?? object.size) - 1;
					const total = object.size;
					headers.set("Content-Range", `bytes ${start}-${end}/${total}`);
					if (r.length !== undefined) {
						headers.set("Content-Length", r.length.toString());
					}

					return new Response(method === "HEAD" || !("body" in object) ? null : object.body, {
						status: 206,
						headers,
					});
				}

				headers.set("Content-Length", object.size.toString());
				return new Response(method === "HEAD" || !("body" in object) ? null : object.body, {
					status: 200,
					headers,
				});
			}

			// 5. Get Thumbnail: GET /thumbnail/:id (or /thumbnail/:id.jpg)
			const thumbMatch = path.match(/^\/thumbnail\/([a-zA-Z0-9_-]+)(?:\.jpg)?$/);
			if (thumbMatch && method === "GET") {
				const uploadId = thumbMatch[1];
				const object = await env.screen_recordings.get(`thumbnails/${uploadId}.jpg`);

				if (!object || !("body" in object)) {
					return new Response("Thumbnail not found", {
						status: 404,
						headers: CORS_HEADERS,
					});
				}

				const headers = new Headers();
				object.writeHttpMetadata(headers);
				headers.set("etag", object.httpEtag);
				for (const [k, v] of Object.entries(CORS_HEADERS)) {
					headers.set(k, v);
				}
				headers.set("Cache-Control", "public, max-age=2592000, immutable");

				return new Response(object.body, { status: 200, headers });
			}

			// 6. Get Recording Metadata: GET /api/recordings/:id
			const metaMatch = path.match(/^\/api\/recordings\/([a-zA-Z0-9_-]+)$/);
			if (metaMatch && method === "GET") {
				const uploadId = metaMatch[1];
				const raw = await env.RECORDING_META.get(`meta:${uploadId}`);
				if (!raw) {
					return jsonResponse({ error: "Recording not found" }, 404);
				}
				return jsonResponse(JSON.parse(raw));
			}

			// 7. Web Video Player Page: GET /r/:id or GET /watch/:id
			const playerMatch = path.match(/^\/(?:r|watch)\/([a-zA-Z0-9_-]+)$/);
			if (playerMatch && method === "GET") {
				const uploadId = playerMatch[1];

				if (isPaused) {
					return new Response(renderMaintenanceHtml("Service Temporarily Paused", "Our cloud video streaming is temporarily paused or at its monthly billing quota. Please check back later."), {
						status: 503,
						headers: { "Content-Type": "text/html; charset=utf-8" },
					});
				}

				const videoHead = await env.screen_recordings.head(`videos/${uploadId}.mp4`);
				if (!videoHead) {
					return new Response(renderMaintenanceHtml("Recording Unavailable", "This video could not be found or has expired. If this was recorded recently in QA Mate, it is stored locally on the recorder's device."), {
						status: 404,
						headers: { "Content-Type": "text/html; charset=utf-8" },
					});
				}

				// Optional metadata lookup
				let title = "Screen Recording";
				let createdAt = "";
				try {
					const raw = await env.RECORDING_META.get(`meta:${uploadId}`);
					if (raw) {
						const meta: RecordingMetadata = JSON.parse(raw);
						title = meta.title || title;
						createdAt = meta.createdAt ? new Date(meta.createdAt).toLocaleDateString(undefined, { dateStyle: "medium" }) : "";
					}
				} catch {
					// Ignore KV lookup errors on display
				}

				const streamUrl = `${origin}/stream/${uploadId}`;
				const thumbUrl = `${origin}/thumbnail/${uploadId}`;
				const shareUrl = `${origin}/r/${uploadId}`;

				const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)} - QA Mate</title>
  
  <!-- Open Graph / Social Embeds -->
  <meta property="og:type" content="video.other">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="Watch screen recording recorded with QA Mate">
  <meta property="og:video" content="${streamUrl}">
  <meta property="og:video:type" content="video/mp4">
  <meta property="og:image" content="${thumbUrl}">
  <meta property="og:url" content="${shareUrl}">
  <meta name="twitter:card" content="player">
  <meta name="twitter:title" content="${escapeHtml(title)}">
  <meta name="twitter:description" content="Watch screen recording recorded with QA Mate">
  <meta name="twitter:image" content="${thumbUrl}">
  <meta name="twitter:player" content="${shareUrl}">
  <meta name="twitter:player:width" content="1280">
  <meta name="twitter:player:height" content="720">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  
  <style>
    :root {
      --bg: #090B10;
      --card-bg: #141721;
      --card-border: #1E2333;
      --primary: #6366F1;
      --primary-hover: #4F46E5;
      --text: #F8FAFC;
      --text-muted: #94A3B8;
      --accent: #10B981;
    }
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body {
      background-color: var(--bg);
      color: var(--text);
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }
    header {
      padding: 18px 28px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--card-border);
      background: rgba(14, 18, 27, 0.85);
      backdrop-filter: blur(12px);
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
      text-decoration: none;
      color: white;
      font-weight: 700;
      font-size: 1.15rem;
      letter-spacing: -0.02em;
    }
    .brand-icon {
      width: 32px;
      height: 32px;
      background: linear-gradient(135deg, #6366F1, #8B5CF6);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 12px rgba(99, 102, 241, 0.4);
    }
    .brand-icon svg {
      width: 18px;
      height: 18px;
      fill: white;
    }
    main {
      flex: 1;
      max-width: 1100px;
      margin: 0 auto;
      width: 100%;
      padding: 32px 20px;
      display: flex;
      flex-direction: column;
      gap: 20px;
    }
    .video-wrapper {
      background: #000;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 20px 40px -15px rgba(0, 0, 0, 0.7), 0 0 0 1px var(--card-border);
      position: relative;
      aspect-ratio: 16 / 9;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      outline: none;
    }
    .meta-card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 24px;
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .meta-info h1 {
      font-size: 1.35rem;
      font-weight: 700;
      color: var(--text);
      margin-bottom: 6px;
    }
    .meta-info p {
      font-size: 0.9rem;
      color: var(--text-muted);
    }
    .action-group {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 18px;
      border-radius: 10px;
      font-size: 0.9rem;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.2s ease;
      border: none;
    }
    .btn-primary {
      background: var(--primary);
      color: white;
    }
    .btn-primary:hover {
      background: var(--primary-hover);
      box-shadow: 0 4px 14px rgba(99, 102, 241, 0.4);
    }
    .btn-secondary {
      background: #1E2333;
      color: var(--text);
      border: 1px solid rgba(255, 255, 255, 0.1);
    }
    .btn-secondary:hover {
      background: #282E44;
    }
    .toast {
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: #10B981;
      color: white;
      padding: 12px 20px;
      border-radius: 10px;
      font-weight: 600;
      font-size: 0.9rem;
      display: none;
      box-shadow: 0 8px 24px rgba(16, 185, 129, 0.4);
      animation: fadeIn 0.25s ease;
      z-index: 100;
    }
    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(10px); }
      to { opacity: 1; transform: translateY(0); }
    }
  </style>
</head>
<body>
  <header>
    <a href="#" class="brand">
      <div class="brand-icon">
        <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 14.5v-9l6 4.5-6 4.5z"/></svg>
      </div>
      <span>QA Mate</span>
    </a>
    <div style="font-size: 0.85rem; color: var(--text-muted);">Cloudflare R2 Streaming</div>
  </header>

  <main>
    <div class="video-wrapper">
      <video controls autoplay playsinline preload="metadata" poster="${thumbUrl}">
        <source src="${streamUrl}" type="video/mp4">
        Your browser does not support the video tag.
      </video>
    </div>

    <div class="meta-card">
      <div class="meta-info">
        <h1>${escapeHtml(title)}</h1>
        <p>${createdAt ? 'Recorded on ' + createdAt + ' • ' : ''}Hosted on Cloudflare R2</p>
      </div>

      <div class="action-group">
        <button class="btn btn-secondary" id="copyBtn" onclick="copyLink()">
          <svg width="16" height="16" fill="currentColor" viewBox="0 0 24 24"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
          <span id="copyText">Copy Link</span>
        </button>

        <a class="btn btn-primary" href="${streamUrl}" download="${uploadId}.mp4">
          <svg width="16" height="16" fill="currentColor" viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/></svg>
          Download
        </a>
      </div>
    </div>
  </main>

  <div id="toast" class="toast">Link copied to clipboard!</div>

  <script>
    function copyLink() {
      navigator.clipboard.writeText(window.location.href).then(() => {
        const toast = document.getElementById('toast');
        toast.style.display = 'block';
        document.getElementById('copyText').innerText = 'Copied!';
        setTimeout(() => {
          toast.style.display = 'none';
          document.getElementById('copyText').innerText = 'Copy Link';
        }, 2500);
      });
    }
  </script>
</body>
</html>`;

				return new Response(html, {
					status: 200,
					headers: {
						"Content-Type": "text/html; charset=utf-8",
					},
				});
			}

			return jsonResponse({ error: "Not Found", path }, 404);
		} catch (err: any) {
			return jsonResponse({ error: err.message || "Internal server error" }, 500);
		}
	},
} satisfies ExportedHandler<Env>;

function escapeHtml(str: string): string {
	return str
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;")
		.replace(/'/g, "&#039;");
}

function renderMaintenanceHtml(title: string, message: string): string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)} - QA Mate</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #090B10;
      --card-bg: #141721;
      --card-border: #1E2333;
      --warning: #F59E0B;
      --text: #F8FAFC;
      --text-muted: #94A3B8;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: var(--bg);
      color: var(--text);
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px;
    }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 20px;
      padding: 40px 32px;
      max-width: 480px;
      width: 100%;
      text-align: center;
      box-shadow: 0 20px 40px -15px rgba(0,0,0,0.6);
    }
    .icon-badge {
      width: 64px;
      height: 64px;
      border-radius: 50%;
      background: rgba(245, 158, 11, 0.15);
      border: 1.5px solid rgba(245, 158, 11, 0.35);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 20px;
    }
    .icon-badge svg { width: 32px; height: 32px; fill: var(--warning); }
    h1 { font-size: 1.35rem; font-weight: 700; margin-bottom: 10px; color: var(--text); }
    p { font-size: 0.95rem; color: var(--text-muted); line-height: 1.5; margin-bottom: 24px; }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      background: rgba(245, 158, 11, 0.15);
      border: 1px solid rgba(245, 158, 11, 0.3);
      border-radius: 12px;
      color: var(--warning);
      font-size: 0.8rem;
      font-weight: 700;
      margin-bottom: 16px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 11px 22px;
      background: #1E2333;
      color: var(--text);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      font-weight: 600;
      text-decoration: none;
      cursor: pointer;
      font-size: 0.9rem;
      transition: all 0.2s ease;
    }
    .btn:hover { background: #282E44; }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon-badge">
      <svg viewBox="0 0 24 24"><path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13h-4v-2h4v2z"/></svg>
    </div>
    <div class="badge">Cloudflare R2 Notice</div>
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(message)}</p>
    <a href="javascript:location.reload()" class="btn">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/></svg>
      Refresh Page
    </a>
  </div>
</body>
</html>`;
}

