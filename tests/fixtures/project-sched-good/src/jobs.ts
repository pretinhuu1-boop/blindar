// FIXTURE SEGURA — job registrado com lock distribuido (redlock), sem @Cron cru.
import { SchedulerRegistry } from '@nestjs/schedule';
export class Jobs {
  constructor(private reg: SchedulerRegistry, private lock: any) {}
  setup() {
    // registra cron via addCronJob adquirindo redlock antes de rodar
    this.lock.acquire('nightly');
  }
}
