# WordPress on CDNTR, driven from the terminal with cdnctl

A short walkthrough for putting a WordPress site on
[CDNTR](https://cdn.com.tr/en) (CDN.com.tr) and keeping it fast with the
[`cdnctl`](https://github.com/mediatriple/cdnctl) command-line tool: what you do in the panel once, and what
you script afterwards (cache purge, checks, CI).

It accompanies two guides: [How to add a CDN to WordPress](https://cdn.com.tr/en/learn/wordpress-cdn-setup)
and [How to speed up a WordPress site](https://cdn.com.tr/en/learn/speed-up-wordpress).

> **Honest scope.** `cdnctl` has no "create a WordPress site" command. Creating the site, attaching the
> domain and importing the database are panel steps (or your own MySQL client). What `cdnctl` is good at
> for WordPress is the day-to-day part: purging exactly the right URLs, from your laptop or CI. Every
> command below exists in `cdnctl` 0.38.0 (checked against its source).

## The problem

A stock WordPress install rebuilds every page with PHP and MySQL on each visit. Under a traffic spike PHP
workers pile up waiting on the database. Caching fixes that, but caching creates its own problem: editors
change a post and still see the old page. So you need two things: a cache in front of WordPress, and a
cheap, precise way to invalidate it.

## Two ways to put WordPress on CDNTR

| | Keep your current host (Pull CDN) | Move the site onto the managed WordPress platform |
|---|---|---|
| Where WordPress runs | Where it runs today | CDNTR [managed WordPress](https://cdn.com.tr/en/features/wordpress-platform): PHP 8, managed MySQL, Redis object cache, Auto SSL |
| What the CDN does | Serves CSS, JS and images from the edge (plugin), or every page (DNS) | The same edge cache, WAF and Auto SSL, already in front of the site |
| You set it up in | Panel + the free CDNTR WordPress plugin | Panel |
| `cdnctl` is for | Purge, checks, CI | Purge, checks, CI |

Both end in the same place for this repository: a cached site and a script that purges the right URLs.

## Architecture

```
visitor --> CDNTR edge (cache, WAF, Auto SSL) --> WordPress (your host or the managed platform)
                 ^
                 +-- cdnctl purge  (laptop or CI, after a publish or a theme deploy)
```

## Step by step

### 1. Install cdnctl and sign in

Install it with your package manager or from the
[cdnctl reference](https://cdn.com.tr/en/help/developers-tools/cdnctl), then:

```sh
cdnctl login                 # browser sign-in
cdnctl accounts ls           # uuid, domain, type of each account
cdnctl accounts use <account_uuid>
cdnctl whoami
```

After `accounts use`, `--account` is optional. The scripts here still pass it explicitly so they are safe in CI.

### 2. Create the site (panel)

- **Keep your host:** open a new CDN account, choose **Pull CDN** and set your current WordPress address as the
  origin ([publish an existing website through the CDN](https://cdn.com.tr/en/help/getting-started/existing-site-cdn)).
  Install the free **CDNTR** plugin in WordPress and approve the site with *Connect to CDN.com.tr*.
- **Move to the managed platform:** in the panel open *Platform*, choose *WordPress*, pick the PHP 8 runtime and
  a plan. wp-content gets a persistent volume and the managed MySQL connection is injected for you. Restore
  your files and import your database dump with the MySQL credentials shown in the panel, and check the site on
  its `name.cdn.com.tr` address before you switch DNS.

`cdnctl container imports` exists, but it is documented for Managed Container Apps, so this repository does not
use it for the WordPress platform.

### 3. Check that caching works

```sh
./scripts/check-cache.sh https://www.example.com/
# request 1: X-Proxy-Cache-MT: MISS
# request 2: X-Proxy-Cache-MT: HIT
```

[`X-Proxy-Cache-MT`](https://cdn.com.tr/en/help/cache-security-purge/cache-status-headers) tells you what the edge
did: HIT, MISS, BYPASS or EXPIRED. A logged-in request or a WooCommerce cart cookie should show BYPASS; that is
the cache keeping carts private, not a bug.

### 4. Purge after you publish or deploy

```sh
export CDNTR_ACCOUNT=<account_uuid>

# a post changed: home page, feed and sitemaps
./scripts/purge-after-deploy.sh

# a theme deploy: also everything under the theme folder
./scripts/purge-after-deploy.sh my-theme
```

The script is just three `cdnctl purge` calls. You can run them by hand:

```sh
cdnctl purge --account <uuid> --path /sitemap.xml                   # one URL
cdnctl purge --account <uuid> --paths "/,/feed/" --type exact       # several URLs
cdnctl purge --account <uuid> --path /wp-content/themes/my-theme/ --type prefix   # a folder and below
cdnctl purge all --account <uuid> --yes                             # everything (last resort)
cdnctl purge all status --account <uuid>
```

`--type` is `exact` (default), `prefix` (the path and everything under it) or `variants` (every stored variant of
the cache key). The CDNTR plugin already purges a post's pages when content changes; the script is for deploys
and for sites where you do not run the plugin.

### 5. Do it from CI

[`.github/workflows/purge-after-deploy.yml`](.github/workflows/purge-after-deploy.yml) installs cdnctl and runs the
script. `cdnctl` reads `CDN_ENDPOINT` and `CDN_ACCESS_TOKEN` from the environment; store your API token (see the
[CDN API guide](https://cdn.com.tr/en/learn/cdn-api)) as the `CDN_ACCESS_TOKEN` secret and the account uuid as
the `CDN_ACCOUNT_UUID` variable.

### 6. Watch for abuse on wp-login.php (optional)

```sh
cdnctl waf logs --account <uuid> --range 1d
```

Brute-force traffic against `wp-login.php` and `xmlrpc.php` is filtered at the edge before it reaches PHP.
See [Read WAF logs](https://cdn.com.tr/en/help/cache-security-purge/waf-logs).

## Pitfalls

**1. "I purged but it is still old."** The cache key includes the query string and host, so `/?utm=x` is a
different entry from `/`. Purge with `--type prefix` for a section, or `--type variants` to remove every stored variant of a URL's cache key, and read
[why a purge does not always show](https://cdn.com.tr/en/help/cache-security-purge/cache-key-and-purge).

**2. Purging the whole site on every publish.** `purge all` empties the cache for every visitor and sends all
of them to your origin at once. Purge the URLs that changed.

**3. Cached admin and cart pages.** Cache rules recognise the WordPress login cookie and the WooCommerce cart and
session cookies and bypass the cache for those requests. If you see logged-in content served to anonymous
visitors, check BYPASS with step 3 before changing anything else.

**4. Theme and plugin updates that keep their file names.** Visitors keep the cached CSS. Purge the theme folder
as a prefix, or make sure the assets carry a version query that WordPress changes on update.

**5. Wrong headers from the origin.** Edge caching follows your cache headers and rules; the
[Cache-Control guide](https://cdn.com.tr/en/learn/cache-control-headers) explains what to send.

## Why this on CDNTR

- Cache, WAF, Auto SSL and DNS in one panel; the managed WordPress stack arrives with MySQL and Redis wired in.
- Your data stays in the region you choose (Türkiye, Europe or the United States), with a Türkiye-only
  processing option and a data processing agreement on request.
- Everything above is scriptable: the same purge runs from a laptop, a deploy hook or CI.

## FAQ

**Do I have to move my site?** No. The Pull CDN route keeps WordPress where it is.
[Compare it with managed hosting](https://cdn.com.tr/en/wordpress-hosting).

**Do I still need a caching plugin?** The edge cache and the Redis object cache cover what page-cache plugins
usually do; see the
[WordPress performance scenario](https://cdn.com.tr/en/features/use-cases/wordpress-performance).

**Can `cdnctl` create the WordPress site?** Not today. Use the panel, then script the rest.

**Is the purge instant?** It is a request that completes asynchronously; `cdnctl purge all status` and the
Operations page show where it is. Verify with step 3.

## Links

- Guides: [Add a CDN to WordPress](https://cdn.com.tr/en/learn/wordpress-cdn-setup) ·
  [Speed up WordPress](https://cdn.com.tr/en/learn/speed-up-wordpress) ·
  [From `cdnctl init` to live](https://cdn.com.tr/en/learn/cdnctl-init-to-live)
- Features: [Managed WordPress platform](https://cdn.com.tr/en/features/wordpress-platform) ·
  [CDN cache](https://cdn.com.tr/en/features/cdn-cache)
- Docs: [Purge cached content](https://cdn.com.tr/en/help/cache-security-purge/purge-content) ·
  [cdnctl](https://cdn.com.tr/en/help/developers-tools/cdnctl)

## License

MIT. See [LICENSE](LICENSE).
