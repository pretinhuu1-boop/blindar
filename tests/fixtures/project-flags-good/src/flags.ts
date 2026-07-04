// FIXTURE SEGURA — sistema dedicado de flags.
import { flags } from './flag-service';
export const showBeta = () => flags.get('beta');
export const showCheckout = () => flags.get('new-checkout');
