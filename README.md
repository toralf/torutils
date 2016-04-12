# torutils
Few tools to derive the status of a Tor relay and more.

*info.py* gives an overview about sthe status of a relays

*ps.py* continuously shows all used exit ports

*err.py* is used t collect data for the issue https://trac.torproject.org/projects/tor/ticket/13603

*hs_hp.py* can be used as a honeypot/mock to simulate a hidden service

## typical call
    $> ./info.py
    $> ./ps.py
    $> ./err.py 
    $> ./hs-hp.py 6697 irc.log 'irc-hs NOTICE * :*** Looking up your hostname...'

## more info
Have a look at https://www.zwiebeltoralf.de/torserver too.

