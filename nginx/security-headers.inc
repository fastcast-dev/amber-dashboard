# Included in every location, because add_header in a location replaces the server-level ones.
# 'unsafe-eval' is needed because Vue 2 compiles the page's templates in the browser.
# connect-src is 'self' only: the page talks to Amber through this server's /api/prices proxy.
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; manifest-src 'self'; worker-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
add_header Permissions-Policy "fullscreen=(self), screen-wake-lock=(self), camera=(), microphone=(), geolocation=(), payment=(), usb=()" always;
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "no-referrer" always;
add_header Cross-Origin-Opener-Policy "same-origin" always;
add_header Cross-Origin-Resource-Policy "same-origin" always;
