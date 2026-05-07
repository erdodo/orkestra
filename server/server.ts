import { createServer } from "http";
import next from "next";
import { initWebSocketServer } from "./lib/websocket-server";

const port = parseInt(process.env.PORT ?? "3081", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  const httpServer = createServer((req, res) => {
    handle(req, res);
  });

  initWebSocketServer(httpServer);

  httpServer.listen(port, () => {
    console.log(
      `> Orkestra sunucu çalışıyor: http://localhost:${port} [${dev ? "geliştirme" : "üretim"}]`
    );
  });
});
