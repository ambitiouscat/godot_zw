import { hilog } from '@kit.PerformanceAnalysisKit';

export const DOMAIN = 0x0000;

export class Logger {
  private tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  info(msg: string, ...args: Object[]): void {
    hilog.info(DOMAIN, this.tag, '%{public}s', this.format(msg, args));
  }

  warn(msg: string, ...args: Object[]): void {
    hilog.warn(DOMAIN, this.tag, '%{public}s', this.format(msg, args));
  }

  error(msg: string, err?: Object): void {
    const detail = err ? `${msg}: ${JSON.stringify(err)}` : msg;
    hilog.error(DOMAIN, this.tag, '%{public}s', detail);
  }

  private format(msg: string, args: Object[]): string {
    return args.length > 0 ? `${msg} ${args.join(' ')}` : msg;
  }
}
