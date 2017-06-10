# torutils
Few tools to derive the status of a Tor relay and more.

## gather data from a Tor process:

*info.py* gives an overview about the status of a relay.

*ps.py* continuously shows exit port usage.

*err.py* collects data for https://trac.torproject.org/projects/tor/ticket/13603 .

##  play with a hidden service

*websvc.sh*, *websvc.py*, *os.sh*, *mock_irc.py*

## play with encrypted ext4 FS

*unlock_tor.sh*

## fuzz testing

*fuzz.sh*

## more info
You need the Python lib Stem (https://stem.torproject.org/index.html) for the python scripts.

