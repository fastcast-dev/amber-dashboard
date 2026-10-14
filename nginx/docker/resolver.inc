# Local `docker run` only (no cluster DNS): public resolvers. The cluster uses ../resolver.inc.
resolver 1.1.1.1 9.9.9.9 valid=60s ipv6=off;
resolver_timeout 5s;
