# Hall of Mirrors

__WARNING: THIS IS NOT READY FOR REAL LIFE USAGE UNLESS YOU DON'T MIND USING
HALF-WRITTEN IN-PROGRESS THINGS THAT MAY POSSIBLY CREATE BREAKING CHANGES IN THE
FUTURE.__


Build your own corner of Versailles; with your data. You remember data, right?
That stuff you keep putting on other company's sites. Assuming that they won't
change. They won't break.

These tools will (eventually) allow you to pull all the relevant data you have
put on a site, and then serve a version of that data as a nice website. These do
not attempt to fully recreate the site, but the data has been pulled and if you
play with the templates enough then you could.

Each folder contains three tools,

- __init__
- __update__
- __serve__

Before doing anything you need to run __[service]/init__. This will get you to
authenticate the tool (usually by copying a code from a url in), then any
preparation that needs to occur. This only needs to be run once.

Now you're logged in you can run __[service]/update__. This pulls all the new
data down. It has a pretty decent default, but you may want to run it with
`--help` to see what options are available.

Once you have you're data you can see it with __[service]/serve__. This spins up a
local version of the site. It isn't a one-one mirror, but should show enough to
be useful.


## State of the hall

_Note: percentages are fairly arbitrary._

### facebook [80%]

Pulls your photos, photos you've been tagged in and the rest of the album those
photos belong too. Needs to get friends' profile picture(s?) to display
also. And some things should be better about the served site, such as next/prev
for photo pages, and maybe add maps.


### flickr [70%]

Pulls your photos. Need to work on getting faves also. Needs to have a page to
select user. And if the URL could remember whether you entered a path alias,
that would be nice. Speed-ups would be good. And a way to navigate/show set
pages, and tag pages. Oh, and pretty up the tag list page, and add similar tags
to each tag page. Special navigation for machine tags maybe? in a tree? Oh yes
and allow wildcard machine tag searches. And pretty up set list pages. Last
thing: add paging for large set pages, it can take a while to render sets with >
100 photos.


### github [0%]


### last.fm [0%]


### pinboard [0%]


### tumblr [80%]

Pulls your data down, but need to work on getting faves and drafts as well. It
sort of pulls local versions of stuff like photos and audio, but it doesn't yet
serve the local audio up. Might eventually work on serving local versions of
videos, but not yet. Apart for that it works pretty well.


### twitter [0%]
