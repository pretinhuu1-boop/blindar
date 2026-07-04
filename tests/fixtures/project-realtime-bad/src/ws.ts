// FIXTURE VULNERAVEL — comentarios neutros.
import { Server } from 'socket.io';
const io = new Server();
io.on('connection', (socket) => { socket.join('room'); });
export default io;
