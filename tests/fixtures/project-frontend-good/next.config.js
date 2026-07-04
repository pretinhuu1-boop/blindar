// FIXTURE SEGURA — CSP + Trusted Types.
module.exports = {
  async headers() {
    return [{
      source: '/(.*)',
      headers: [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; require-trusted-types-for 'script'",
      }],
    }];
  },
};
