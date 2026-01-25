import asyncio
import websockets
import mss
import cv2
import numpy as np
import time


async def stream_screen(websocket):
    print("Client connected...")

    with mss.mss() as sct:
        monitor = sct.monitors[1]
        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 88]

        # 🔥 记录上一帧的极小缩略图，用来对比画面是否变化
        last_thumb = None

        try:
            while True:
                start_time = time.time()

                # 1. 抓图并缩放到 1080P (1920宽)
                img = np.array(sct.grab(monitor))
                height, width = img.shape[:2]
                if width > 1920:
                    scale = 1920 / width
                    img = cv2.resize(img, (1920, int(height * scale)), interpolation=cv2.INTER_LINEAR)

                # 2. 去除透明通道
                frame = cv2.cvtColor(img, cv2.COLOR_BGRA2BGR)

                # 🔥 3. 核心黑科技：画面防抖检测 🔥
                # 快速把画面缩小到 64x64 像素来计算差异，极度省 CPU
                current_thumb = cv2.resize(frame, (64, 64), interpolation=cv2.INTER_NEAREST)

                send_frame = True
                if last_thumb is not None:
                    # 计算当前帧和上一帧的区别
                    diff = cv2.absdiff(current_thumb, last_thumb)
                    # 如果画面变化极小（阈值小于 2），说明是静止的，直接丢弃这帧！
                    if np.mean(diff) < 2.0:
                        send_frame = False

                last_thumb = current_thumb  # 更新上一帧

                # 🔥 4. 只有画面动了，才占用网络发送！
                if send_frame:
                    _, buffer = cv2.imencode('.jpg', frame, encode_param)
                    await websocket.send(buffer.tobytes())

                # 5. 严格控时
                cost_time = time.time() - start_time
                await asyncio.sleep(max(0, 0.016 - cost_time))

        except websockets.exceptions.ConnectionClosed:
            print("Client disconnected.")


async def main():
    # ping_timeout 设大一点，防止静止时不发包导致断线
    async with websockets.serve(stream_screen, "0.0.0.0", 8765, ping_timeout=60):
        print("[Smart Edition] Screen engine ready...")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())