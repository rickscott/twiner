#!/usr/bin/perl 

use strict;
use warnings;
use 5.10.0;

use Net::Twitter;
use JSON qw{decode_json};
use File::Slurp qw{slurp};
use DateTime;
use Data::Dumper;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

# TODO: rate limiting >< 



# runaway protection: history only goes 3200 tweets back; 3200/200 = 16 pgs
my $MAX_PAGES_TO_FETCH = 16;

my $tweets_to_fetch = parse_config('config.json');


my $twitter = Net::Twitter->new(
      traits   => [qw{API::REST}],
);

my %tweet_pile;  

# fetch tweets (200/page) starting at the newest tweet we want (end_tweet).
# continue fetching until we go past the oldest one we want (start_tweet).
foreach my $user (@$tweets_to_fetch) {
    PAGE:
    for (my $page = 1; $page <= $MAX_PAGES_TO_FETCH; $page++) {
        say STDERR "Fetching page $page for " . $user->{screen_name} . ".";
        my @tweets = fetch_tweets($user->{screen_name}, $user->{end_tweet}, $page);
        my $newest_tweet = $tweets[0]->{id};
        my $oldest_tweet = $tweets[-1]->{id};

        # keep only tweets newer than the oldest tweet we want.
        say STDERR "  > Considering tweets $newest_tweet -- $oldest_tweet.";
        @tweets = grep { $_->{id} >= $user->{start_tweet} } @tweets;
        say STDERR "  > Keeping " . scalar @tweets . " tweets.";

        # throw them onto the tweet pile
        foreach my $tweet (@tweets) {
            $tweet_pile{$tweet->{id}} = $tweet;
        }

        # if the id of the oldest tweet we fetched is less than 
        # the id of the oldest tweet that was asked for, we've fetched 
        # far enough back -- all done.  
        if ($oldest_tweet <= $user->{start_tweet}) {
            last PAGE;
        }
    }
}

# now that we have our pile of tweets, present it

my @timeline = sort keys %tweet_pile;

say q{<html><head></head><body><ul>};

foreach my $id (@timeline) {
    say format_tweet($tweet_pile{$id});
}

say q{</ul></body></html>};



### end of program flow ### 

sub parse_config {
    my $filename = shift;

    open (my $cfg_file, '<:utf8', $filename) or die 'Oh, bother.';
    my $config = slurp($cfg_file);
    close $cfg_file;
    return decode_json($config);
} 

sub fetch_tweets {
    my $screen_name  = shift;
    my $end_tweet    = shift;
    my $page         = shift;
    
    my $tweet_list = $twitter->user_timeline({ 
        screen_name => $screen_name,
        count       => 200,   
        skip_user   => 'true',
        max_id      => $end_tweet,
        page        => $page,
    });

    return map {filter_tweet($screen_name, $_)} @$tweet_list;
}

# reduce the number of fields in an incoming tweet to the ones we're
# interested in. 
sub filter_tweet {
    my $screen_name = shift;
    my $tweet       = shift;

    return {
        screen_name => $screen_name,
        id          => $tweet->{id},
        text        => $tweet->{text},
        created_at  => $tweet->{created_at},
        uri         => "http://twitter.com/$screen_name/statuses/" . $tweet->{id},
    };
}


# admittedly grotty.  would use something like TT if this wasn't a 
# standalone script

sub format_tweet {
    my $tweet = shift;
    return sprintf qq{
  <li style="margin: 1em;">
    <strong>%s</strong>: %s 
    <br />
    <a href="%s">
    <span style="font-size: 75%;">%s</span> 
    </a>
  </li>

    }, $tweet->{screen_name}, $tweet->{text}, $tweet->{uri}, $tweet->{created_at};
}
