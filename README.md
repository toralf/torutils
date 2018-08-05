# torutils
Few tools around a Tor relay.

### gather data from a Tor process:

*info.py* gives an overview about the status of a relay.

*ps.py* continuously shows exit port usage.

*orstatus.py* collects data for https://trac.torproject.org/projects/tor/ticket/13603 .

### simple setup of an onion service

*websvc.sh*, *websvc.py*, *os.sh*, *mock_irc.py*

Running

    ./websvc.sh; ./os.sh

should give you a HTTP onion service.
All files are created under /tmp/.
Verify it with

    tail -f /tmp/websvc.d/websvc.log /tmp/onionsvc.d/notice.log

and

    telnet 127.0.0.1 1234
    ...
    GET / HTTP/1.1

### fuzz testing of the Tor sources

*fuzz.sh*

### more info
You need the Python lib Stem (https://stem.torproject.org/index.html) for the python scripts.

