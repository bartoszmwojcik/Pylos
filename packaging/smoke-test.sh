#!/usr/bin/env bash
# Check the release files on a clean Ubuntu 24.04 (E07-S02, A07).
#
# Usage, inside a fresh container (the release workflow does this):
#   docker run --rm -v "$PWD:/repo" -w /repo ubuntu:24.04 \
#     bash packaging/smoke-test.sh dist/pylos_<version>_amd64.deb dist/pylos-web-<version>-linux-amd64.tar.gz
#
# For each of the two files it installs or unpacks it, starts pylos-web from
# a folder with no web/ in it, and checks over HTTP that:
#   - the page and one of its scripts are served (D26 found the web files);
#   - a bot-vs-bot game started through the API plays to the end.
# Any failure stops with a non-zero exit, and the workflow then publishes
# nothing.
#
# It installs nothing besides the package itself: HTTP is spoken through
# bash's /dev/tcp, so curl's own libraries cannot hide a library the .deb
# forgot to declare.
set -euo pipefail

deb=$1
tarball=$2
port=8080

fail() { echo "smoke-test: FAIL: $*" >&2; exit 1; }

# http METHOD PATH [BODY]: print the whole response (status line, headers,
# body). HTTP/1.0, so the server closes the connection after answering.
http() {
  local method=$1 path=$2 body=${3:-}
  exec 3<>"/dev/tcp/127.0.0.1/$port"
  if [ -n "$body" ]; then
    printf '%s %s HTTP/1.0\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s' \
      "$method" "$path" "${#body}" "$body" >&3
  else
    printf '%s %s HTTP/1.0\r\nHost: localhost\r\n\r\n' "$method" "$path" >&3
  fi
  cat <&3
  exec 3<&-
}

# expect STATUS RESPONSE: the status line carries the code.
expect() {
  local want=$1 response=$2 line
  line=$(printf '%s' "$response" | head -n 1)
  case "$line" in
    *" $want "*) ;;
    *) fail "expected HTTP $want, got: $line" ;;
  esac
}

# check COMMAND...: start the server with COMMAND in an empty folder, run the
# HTTP checks, stop it.
check() {
  local run
  run=$(mktemp -d)
  (cd "$run" && exec "$@" "$port") >"$run/log" 2>&1 &
  local pid=$!
  # Wait up to 10 s for the port to open.
  for _ in $(seq 1 50); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then break; fi
    kill -0 "$pid" 2>/dev/null || { cat "$run/log" >&2; fail "pylos-web exited at start-up"; }
    sleep 0.2
  done
  cat "$run/log"

  expect 200 "$(http GET /)"
  expect 200 "$(http GET /static/app.js)"
  expect 200 "$(http GET /static/vendor/three.module.min.js)"

  local created id snapshot
  created=$(http POST /api/games '{"white":"random","black":"random","delayMs":0,"plyCap":100}')
  expect 201 "$created"
  id=$(printf '%s' "$created" | sed -n 's/.*"id":"\([0-9]*\)".*/\1/p')
  [ -n "$id" ] || fail "no game id in: $created"
  for _ in $(seq 1 50); do
    snapshot=$(http GET "/api/games/$id")
    case "$snapshot" in *'"status":"finished"'*) break ;; esac
    sleep 0.2
  done
  case "$snapshot" in
    *'"status":"finished"'*) echo "smoke-test: game $id played to the end" ;;
    *) fail "game $id did not finish: $snapshot" ;;
  esac

  kill "$pid"
  wait "$pid" 2>/dev/null || true
}

echo "== .deb: $deb"
apt-get update -qq
# apt resolves the Depends line from the Ubuntu archive, as on a user's machine.
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "./${deb#./}"
if ldd /usr/bin/pylos-web | grep -q 'not found'; then
  ldd /usr/bin/pylos-web >&2
  fail "pylos-web needs a library the package does not pull in"
fi
check pylos-web

echo "== .tar.gz: $tarball"
unpack=$(mktemp -d)
tar -C "$unpack" -xzf "$tarball"
# Hide the .deb's copy, so the archive must find its own web/ (D26, step 2).
mv /usr/share/pylos/web /usr/share/pylos/web.hidden
check "$(echo "$unpack"/pylos-web-*/pylos-web)"
mv /usr/share/pylos/web.hidden /usr/share/pylos/web

echo "smoke-test: OK"
