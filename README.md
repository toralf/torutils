# torutils
Few tools to derive the status of a Tor relay and more.

*info.py* gives an overview about sthe status of a relays

*ps.py* continuously shows all used exit ports

*err.py* is used to collect data for https://trac.torproject.org/projects/tor/ticket/13603

*hs-hp.py* is a simple honeypot of a hidden service

## typical call
    $> ./info.py
    $> ./ps.py
    $> ./err.py 
    $> ./hs-hp.py 6697 irc.log 'irc-hs NOTICE * :*** Looking up your hostname...'

## more info
You need the Python lib Stem : https://stem.torproject.org/index.html for few of these scripts to run.

