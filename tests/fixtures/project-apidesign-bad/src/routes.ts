// FIXTURE VULNERAVEL — comentarios neutros.
import { Router } from 'express';
const router = Router();
router.post('/webhook', (req, res) => res.json({ ok: true }));
export default router;
