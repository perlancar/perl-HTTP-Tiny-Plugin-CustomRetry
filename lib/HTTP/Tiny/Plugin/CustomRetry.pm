package HTTP::Tiny::Plugin::CustomRetry;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Time::HiRes qw(sleep);

sub after_request {
    my ($self, $r) = @_;

    $r->{config}{retry_if} //= qr/^5/;
    $r->{config}{strategy} or die "Please set configuration: 'stategy'";

    $r->{_backoff} //= do {
        my $pkg = "Algorithm::Backoff::$r->{config}{strategy}";
        (my $pkg_pm = "$pkg.pm") =~ s!::!/!g;
        require $pkg_pm;
        $pkg->new(%{$r->{config}{strategy_options} // {}});
    };

    my ($http, $method, $url, $options) = @{ $r->{argv} };

    my $fail;
    if (ref $r->{config}{retry_if} eq 'Regexp') {
        $fail = $r->{response}{status} =~ $r->{config}{retry_if};
    } else {
        $fail = $r->{config}{retry_if}->($self, $r->{response});
    }
    if ($fail) {
        my $secs = $r->{_backoff}->failure;
        if ($secs == -1) {
            log_trace "Failed requesting %s (%s - %s), giving up",
                $url,
                $r->{response}{status},
                $r->{response}{reason};
            return 0;
        }
        log_trace "Failed requesting %s (%s - %s), retrying in %.1f second(s) (attempt #%d) ...",
            $url,
            $r->{response}{status},
            $r->{response}{reason},
            $secs,
            $r->{_backoff}{_attempts}+1;
        sleep $secs;
        return 98; # repeat request()
    } else {
        $r->{_backoff}->success;
    }
    1; # ok
}

1;
# ABSTRACT: Retry failed request

=for Pod::Coverage .+

=head1 SYNOPSIS

 use HTTP::Tiny::Plugin 'CustomRetry' => {
     strategy         => 'Exponential',
     strategy_options => {initial_delay=>2, max_delay=>100},
     retry_if         => qr/^[45]/, # optional, default is only 5xx errors are retried
 };

 my $res  = HTTP::Tiny::Plugin->new->get("http://www.example.com/");


=head1 DESCRIPTION

B<DEPRECATION NOTICE:> This plugin is now deprecated, in favor of
L<HTTP::Tiny::Plugin::Retry> which will merge its features.

This plugin retries failed response using one of available backoff strategy in
C<Algorithm::Backoff::*> (e.g. L<Algorithm::Backoff::Exponential>).

By default only retries 5xx failures, as 4xx are considered to be client's fault
(but you can configure it with L</retry_if>).


=head1 CONFIGURATION

=head2 strategy

Str. Name of backoff strategy, which corresponds to
Algorithm::Backoff::<strategy>.

=head2 strategy_options

Hashref. Will be passed to Algorithm::Backoff::* constructor.

=head2 retry_if

Regex or code. If regex, then will be matched against response status. If code,
will be called with arguments: C<< ($self, $response) >>.


=head1 ENVIRONMENT


=head1 SEE ALSO

L<HTTP::Tiny::Plugin>

L<HTTP::Tiny::Plugin::Retry>.
