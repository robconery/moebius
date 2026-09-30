# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 5.x | yes |
| 4.x and earlier | no; please upgrade (4.x depends on packages with known CVEs) |

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private reporting instead: go to the [Security tab](https://github.com/robconery/moebius/security) and click **Report a vulnerability**.

Include the smallest code that shows the problem and what an attacker could do with it. You'll get a reply as soon as a maintainer can look at it, and credit in the changelog when it's fixed (unless you'd rather not).

## What counts

Moebius builds SQL, so SQL injection is the big one. Every value is meant to be sent as a parameter and every table, column and function name is meant to pass `Moebius.Identifier`. If you can get anything into the SQL text some other way, that's a vulnerability and we want to hear about it.

SQL you write yourself (`filter("price > $1", 10)`, `run("select ...")`, SQL files) is used exactly as written, by design. Interpolating user input into those strings is unsafe, the same as it would be with any driver.
