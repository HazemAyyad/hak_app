const haqApiBase = String.fromEnvironment(
  'HAQ_API_BASE_URL',
  // Current hosting serves Laravel under /public. Keep the explicit build
  // override for the clean /api URL once the host document root is corrected.
  defaultValue: 'https://hak.dr-bike.shop/public/api',
);
