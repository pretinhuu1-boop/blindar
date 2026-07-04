// FIXTURE VULNERAVEL — comentarios neutros.
import multer from 'multer';
export const upload = multer({ dest: 'uploads/' });
export const s3opts = { ACL: 'public-read' };
