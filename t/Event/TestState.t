#!/usr/bin/env perl -w

use strict;
use warnings;

use lib 't/lib';

BEGIN { require "t/test.pl" }

use MyEventCollector;
use TB2::Formatter::Null;
use TB2::Events;

my $CLASS = 'TB2::TestState';
use_ok $CLASS;


note "new() does not work"; {
    ok !eval { $CLASS->new; };
    like $@, qr{^\QSorry, there is no new()};
}


note "create() and pass through"; {
    require TB2::History;
    my $state = $CLASS->create(
        formatters => [],
        history    => TB2::History->new( store_events => 1 )
    );

    is_deeply $state->formatters, [],           "create() passes arguments through";
    isa_ok $state->history, "TB2::History";

    my $start = TB2::Event::TestStart->new;
    $state->post_event($start);
    is_deeply $state->history->events, [$start],        "events are posted";
}


note "default"; {
    my $default1 = $CLASS->default;
    my $default2 = $CLASS->default;
    my $new1 = $CLASS->create;
    my $new2 = $CLASS->create;

    is $default1, $default2, "default returns the same object";
    isnt $default1, $new1,     "create() does not return the default";
    isnt $new1, $new2,           "create() makes a fresh object";
}


note "can"; {
    # Test both $class->can and $object->can
    for my $thing ($CLASS, $CLASS->create) {
        can_ok $thing, "formatters";
        can_ok $thing, "create";
        can_ok $thing, "pop_coordinator";

        ok !$thing->can("method_not_appearing_in_this_film");
    }
}


note "push/pop coordinators"; {
    my $state = $CLASS->create;

    my $first_ec  = $state->ec;
    my $second_ec = $state->push_coordinator;
    is $state->history, $second_ec->history;
    isnt $state->history, $first_ec->history;

    is $state->pop_coordinator, $second_ec;
    is $state->history, $first_ec->history;
}


note "push our own coordinator"; {
    my $state = $CLASS->create;

    require TB2::EventCoordinator;
    my $ec = TB2::EventCoordinator->new;

    $state->push_coordinator($ec);

    is $state->ec, $ec;
}


note "popping the last coordinator"; {
    my $state = $CLASS->create;

    ok !eval { $state->pop_coordinator; 1 };
    like $@, qr{^The last coordinator cannot be popped};
}


note "basic subtest"; {
    my $state = $CLASS->create(
        formatters => [],
        history    => TB2::History->new( store_events => 1 )
    );

    note "...starting a subtest";
    my $first_ec = $state->ec;
    my $subtest_start = TB2::Event::SubtestStart->new;
    $state->post_event($subtest_start);
    my $second_ec = $state->ec;

    isnt $first_ec, $second_ec, "creates a new coordinator";

    note "...checking coordinator state";
    my $first_history  = $first_ec->history;
    my $second_history = $second_ec->history;
    is $first_history->event_count, 2;
    my($test_start, $event) = @{$first_history->events};
    is $test_start->event_type, "test_start";
    is $event->object_id, $subtest_start->object_id;
    is $event->event_type, "subtest_start",     "first level saw the start event";
    is $event->depth, 1,                        "  depth was correctly set";
    is $second_history->event_count, 0,     "second level did not see the start event";


    note "...ending the subtest";
    my $subtest_end = TB2::Event::SubtestEnd->new;
    $state->post_event($subtest_end);
    is $subtest_end->history, $second_history,  "second level history attached to the event";
    is $second_history->event_count, 0,         "  second level did not see the end event";
    is $state->ec, $first_ec,  "stack popped";

    is $first_history->event_count, 3;
    $event = $first_history->events->[2];
    is $event->object_id, $subtest_end->object_id;
    is $event->event_type, "subtest_end",     "first level saw the start event";
    is $event->history, $second_history;
}


note "honor event presets"; {
    my $state = $CLASS->create(
        formatters => [],
        history    => TB2::History->new( store_events => 1 )
    );

    note "...post a subtest with a pre defined depth";
    my $subtest_start = TB2::Event::SubtestStart->new(
        depth => 93
    );
    my $history = $state->history;
    $state->post_event($subtest_start);
    is $history->events->[1]->depth, 93;

    note "...post a subtest with a alternate history";
    my $alternate_history = TB2::History->new;
    my $subtest_end = TB2::Event::SubtestEnd->new(
        history => $alternate_history
    );
    $state->post_event($subtest_end);
    is $state->history->events->[-1]->history, $alternate_history;
}


note "nested subtests"; {
    my $state = $CLASS->create(
        formatters => [],
        history    => TB2::History->new( store_events => 1 )
    );

    my $first_stream_start = TB2::Event::TestStart->new;
    $state->post_event($first_stream_start);

    my $first_subtest_start = TB2::Event::SubtestStart->new;
    $state->post_event($first_subtest_start);
    is $first_subtest_start->depth, 1;

    my $second_stream_start = TB2::Event::TestStart->new;
    $state->post_event($second_stream_start);

    my $second_subtest_start = TB2::Event::SubtestStart->new;
    $state->post_event($second_subtest_start);
    is $second_subtest_start->depth, 2;

    my $second_subtest_ec = $state->ec;

    my $second_subtest_end = TB2::Event::SubtestEnd->new;
    $state->post_event($second_subtest_end);
    is $second_subtest_end->history, $second_subtest_ec->history;

    my $second_stream_end = TB2::Event::TestEnd->new;
    $state->post_event($second_stream_end);

    my $first_subtest_ec = $state->ec;

    my $first_subtest_end = TB2::Event::SubtestEnd->new;
    $state->post_event($first_subtest_end);
    is $first_subtest_end->history, $first_subtest_ec->history;

    my $first_stream_end = TB2::Event::TestEnd->new;
    $state->post_event($first_stream_end);

    is_deeply [map { $_->event_type } @{$state->history->events}],
              ["test_start", "subtest_start", "subtest_end", "test_end"],
              "original level saw the right events";

    is_deeply [map { $_->event_type } @{$first_subtest_ec->history->events}],
              ["test_start", "subtest_start", "subtest_end", "test_end"],
              "first subtest saw the right events";

    is_deeply [map { $_->event_type } @{$second_subtest_ec->history->events}],
              [],
              "second subtest saw the right events";
}


note "handlers providing their own subtest_handler"; {
    # Some classes useful for testing subtest_handler is called correctly
    {
        package MyHistory;
        use TB2::Mouse;
        extends "TB2::History";

        has denial =>
          is            => 'rw',
          isa           => 'Int';

        # Just something to know the handler got called
        sub subtest_handler {
            my $self = shift;
            my $event = shift;

            ::isa_ok $event, "TB2::Event::SubtestStart";

            return $self->new( denial => 5 );
        }
    }

    {
        package MyNullFormatter;
        use TB2::Mouse;
        extends "TB2::Formatter::Null";

        has depth => 
          is            => 'rw',
          isa           => 'Int',
          default       => 0;

        # Just something to know the handler got called
        sub subtest_handler {
            my $self = shift;
            my $event = shift;

            ::isa_ok $event, "TB2::Event::SubtestStart";

            return $self->new( depth => $event->depth );
        }
    }

    {
        package MyEventCollectorSeesAll;
        use TB2::Mouse;
        extends "MyEventCollector";

        # A handler that returns itself
        sub subtest_handler {
            my $self = shift;
            my $event = shift;

            ::isa_ok $event, "TB2::Event::SubtestStart";

            return $self;
        }
    }

    note "...init a bunch of handlers with subtest_handler overrides";
    my $formatter1 = TB2::Formatter::Null->new;
    my $formatter2 = MyNullFormatter->new;
    my $seesall    = MyEventCollectorSeesAll->new;
    my $collector  = MyEventCollector->new;
    my $history   = MyHistory->new( store_events => 1 );
    my $state = $CLASS->create(
        formatters      => [$formatter1, $formatter2],
        history         => $history,
        early_handlers  => [$formatter2, $seesall],
        late_handlers   => [$formatter2, $collector],
    );

    note "...starting the subtest";
    my $subtest_start = TB2::Event::SubtestStart->new;
    $state->post_event($subtest_start);

    note "...checking the sub handlers were initialized from their parent's classes";
    isa_ok $state->formatters->[0],     ref $formatter1;
    isa_ok $state->formatters->[1],     ref $formatter2;
    isa_ok $state->history,             ref $history;
    isa_ok $state->early_handlers->[0], ref $formatter2;
    isa_ok $state->early_handlers->[1], ref $seesall;
    isa_ok $state->late_handlers->[0],  ref $formatter2;
    isa_ok $state->late_handlers->[1],  ref $collector;

    note "...checking the sub handlers made new objects (or didn't)";
    isnt $state->formatters->[0],     $formatter1;
    isnt $state->formatters->[1],     $formatter2;
    isnt $state->history,             $history;
    isnt $state->early_handlers->[0], $formatter2;
    is   $state->early_handlers->[1], $seesall;
    isnt $state->late_handlers->[0],  $formatter2;
    isnt $state->late_handlers->[1],  $collector;

    note "...checking special subtest_handler methods were called";
    is $state->formatters->[1]->depth,          1;
    is $state->history->denial,                 5;
    is $state->early_handlers->[0]->depth,      1;
    is $state->late_handlers->[0]->depth,       1;

    # Start and end an empty subtest
    my $substream_start = TB2::Event::SubtestStart->new;
    my $substream_end = TB2::Event::SubtestEnd->new;
    $state->post_event($_) for $substream_start, $substream_end;
    my $substream_test_start = $state->history->test_start;

    my $subtest_end = TB2::Event::SubtestEnd->new;
    $state->post_event($subtest_end);

    is_deeply [map { $_->object_id } $state->history->test_start, $subtest_start, $subtest_end],
              [map { $_->object_id } @{$history->events}];

    my @all_events = (
        $state->history->test_start,
        $subtest_start,
            $substream_test_start,
            $substream_start,
            $substream_end,
        $subtest_end
    );
    is_deeply [map { $_->object_id } @all_events],
              [map { $_->object_id } @{$seesall->events}],
              "A handler can see all if it chooses";
}

note "object_id"; {
    my $state1 = $CLASS->create;
    my $state2 = $CLASS->create;

    ok $state1->object_id;
    ok $state2->object_id;

    isnt $state1->object_id, $state2->object_id, "teststate object_ids are unique";

    require TB2::EventCoordinator;
    my $ec = TB2::EventCoordinator->new;

    cmp_ok( $state1->object_id, '=~', '^TB2-TestState', 'object_id is ours' );

    my $state1_id = $state1->object_id;
    $state1->push_coordinator($ec);

    is $state1->object_id, $state1_id, 'object_id stays the same after changing coordinators';
}


note "coordinate_forks in constructor"; {
    # There was a bug in which this would error out
    my $State = TB2::TestState->create(
        formatters => [],
        coordinate_forks => 1
    );
    pass();
}

done_testing;
