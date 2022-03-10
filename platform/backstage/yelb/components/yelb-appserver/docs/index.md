# yelb appserver

This is the application server. It's a Ruby/Sinatra application that exposes a number of APIs that are consumed by the UI (or via curl if you fancy that). It reads and writes to a cache server (redis-server) as well as a Postgres backend database (yelb-db).

Originally this application was included in a single file (`yelb-appserver.rb`). This has been since refactored by extracting the single API definition in their separate adapters and modules. This made the transition to Lambda/Serverless easier (one lambda per API definition). This hasn't changed the other deployment models (containers and instances) because those models still launch the `yelb-appserver.rb` main application which imports the modules instead of having everything in a single file (as it was conceived originally).

# yelb

This sample catalog and documentation corresponds to a demonstration application called [Yelb](https://github.com/mreferre/yelb).