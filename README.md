16pieces is a [Yesod](http://www.yesodweb.com) webapp that makes it easy to play chess with someone you know.

You can play at [16pieces.com](http://www.16pieces.com).

## Building

After cloning the 16pieces git repository, you can build it with cabal:
    
    cd 16pieces
    cabal sandbox init
    cabal install
    
And run it:

    ./dist/build/16pieces/16pieces
    
Then visit [http://localhost:3000](http://localhost:3000) with your browser.
