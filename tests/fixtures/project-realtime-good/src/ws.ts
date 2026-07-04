// FIXTURE SEGURA — comentarios neutros.
import { Server } from 'socket.io';
const io = new Server({ pingInterval: 25000, pingTimeout: 20000 });
io.on('connection', (socket) => { verifyToken(socket); socket.join('tenant:1'); });
declare function verifyToken(s: unknown): void;
export default io;
