# Hall of Mirrors

A suite of tools to backup your data on various websites.

Each folder contains three tools,

- __init__
- __update__
- __serve__

Before doing anything you need to run __service/init__. This will get you to
authenticate the tool (usually by copying a code from a url in), then any
preparation that needs to occur. This only needs to be run once.

Now you're logged in you can run __service/update__, this pulls all the new data
down. It has a pretty decent default, but you may want to run it with `--help`
to see what options are available.

Once you have you're data you can see it with __service/serve__. This spins up a
local version of the site. It isn't a one-one mirror, but should show enough to
be useful.
