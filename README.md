# Debian / Postfix

**Postfix** is Wietse Venema's mail transport agent that started life as an alternative to the widely-used Sendmail program. Postfix attempts to be fast, easy to administer, and secure, while at the same time being sendmail compatible enough to not upset existing users. Thus, the outside has a sendmail-ish flavor, but the inside is completely different.

## How to Build

1. Get source from [salsa.debian.org](https://salsa.debian.org/postfix-team/postfix-dev).
2. Write changelog (`git log --decorate=full > git.debian.log`) from [salsa.debian.org](https://salsa.debian.org/postfix-team/postfix-dev) to [git.debian.log](git.debian.log).
3. Modify & update source.
4. Build source.
