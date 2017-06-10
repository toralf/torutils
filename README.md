# torutils
Few tools to derive the status of a Tor relay and more.

*info.py* gives an overview about the status of a relay.

*ps.py* continuously shows exit port usage.

*err.py* collects data for https://trac.torproject.org/projects/tor/ticket/13603 .

## typical call
    $> ./info.py
    $> ./ps.py
    $> ./err.py 

## more info
You need the Python lib Stem (https://stem.torproject.org/index.html) for the python scripts.

