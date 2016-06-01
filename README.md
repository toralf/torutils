# torutils
Few tools to derive the status of a Tor relay and more.

*info.py* gives an overview about the status of a relays.

*ps.py* continuously shows exit port usage.

*err.py* collects data for https://trac.torproject.org/projects/tor/ticket/13603

*hs-hp.py* helps to play with network services.

## typical call
    $> ./info.py
    $> ./ps.py
    $> ./err.py 
    $> ./hs-hp.py 6697 irc.log 'irc-hs NOTICE * :*** Looking up your hostname...'

## more info
You need the Python lib Stem : https://stem.torproject.org/index.html for most of these scripts to run.

