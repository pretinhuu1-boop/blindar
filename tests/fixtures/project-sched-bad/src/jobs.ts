// FIXTURE VULNERAVEL — cron sem lock distribuido.
import { Cron } from '@nestjs/schedule';
export class Jobs {
  @Cron('0 0 * * *')
  async run() {
    await doWork();
  }
}
declare function doWork(): Promise<void>;
