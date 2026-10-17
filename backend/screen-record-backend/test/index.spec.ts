import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
	SELF,
} from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker from "../src/index";

const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

describe("Screen Recording Backend with R2 and KV", () => {
	it("responds with health check on GET /", async () => {
		const request = new IncomingRequest("http://example.com/");
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);

		expect(response.status).toBe(200);
		const data = (await response.json()) as any;
		expect(data.status).toBe("ok");
		expect(data.r2Bucket).toBe("screen-recordings");
	});

	it("initializes upload and uploads video + thumbnail to R2, then streams it", async () => {
		const ctx = createExecutionContext();

		// 1. Initialize upload session
		const initReq = new IncomingRequest("http://example.com/api/upload/init", {
			method: "POST",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify({
				title: "Bug Reproduction Video",
				video: { contentType: "video/mp4", fileSize: 1024 },
				thumbnail: { contentType: "image/jpeg", fileSize: 512 },
			}),
		});

		const initResp = await worker.fetch(initReq, env, ctx);
		expect(initResp.status).toBe(201);
		const initData = (await initResp.json()) as any;
		expect(initData.uploadId).toBeDefined();
		expect(initData.videoUploadUrl).toContain(`/api/upload/${initData.uploadId}/video`);
		expect(initData.playerUrl).toContain(`/r/${initData.uploadId}`);

		const uploadId = initData.uploadId;

		// 2. PUT video binary
		const fakeVideoBytes = new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
		const videoReq = new IncomingRequest(`http://example.com/api/upload/${uploadId}/video`, {
			method: "PUT",
			headers: { "Content-Type": "video/mp4" },
			body: fakeVideoBytes,
		});
		const videoResp = await worker.fetch(videoReq, env, ctx);
		expect(videoResp.status).toBe(200);

		// 3. GET video stream
		const streamReq = new IncomingRequest(`http://example.com/stream/${uploadId}`);
		const streamResp = await worker.fetch(streamReq, env, ctx);
		expect(streamResp.status).toBe(200);
		expect(streamResp.headers.get("Accept-Ranges")).toBe("bytes");
		const streamBytes = new Uint8Array(await streamResp.arrayBuffer());
		expect(streamBytes.length).toBe(fakeVideoBytes.length);

		// 4. GET video player HTML
		const playerReq = new IncomingRequest(`http://example.com/r/${uploadId}`);
		const playerResp = await worker.fetch(playerReq, env, ctx);
		expect(playerResp.status).toBe(200);
		expect(playerResp.headers.get("Content-Type")).toContain("text/html");
		const html = await playerResp.text();
		expect(html).toContain("QA Mate");
		expect(html).toContain(`/stream/${uploadId}`);
		expect(html).toContain("Bug Reproduction Video");

		await waitOnExecutionContext(ctx);
	});
});
