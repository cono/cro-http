use Cro::HTTP::Log::File;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use Test;

constant TEST_PORT = 31313;
my $url = "http://localhost:{TEST_PORT}";

my $app = route {
    get -> {
        content 'text/html', 'My response';
    }
    get -> 'route' {
        content 'text/plain', 'My response';
    }
    post -> 'route' {
        content 'text/plain', 'My response';
    }
    get -> 'error' {
        die 'No more'
    }
}

{
    my $out = open 'out'.IO, :w;
    my $err = open 'err'.IO, :w;

    use Cro::HTTP::Log::File;
    my $logger =  Cro::HTTP::Log::File.new(:$out, :$err);

    my $service = Cro::HTTP::Server.new(
        :host('localhost'), :port(TEST_PORT), application => $app,
        after => Cro::HTTP::Log::File.new(:$out, :$err)
    );

    $service.start;

    my $completed = Promise.new;

    start {
        use Cro::HTTP::Client;
        await Cro::HTTP::Client.get("$url");
        await Cro::HTTP::Client.get("$url/route");
        await Cro::HTTP::Client.post("$url/route");
        await Cro::HTTP::Client.get("$url/error");
        CATCH {
            default {
                # The last await was thrown
                $completed.keep;
            }
        }
    }

    await Promise.anyof($completed, Promise.in(5));

    $out.close; $err.close;

    is (slurp 'out'), "[OK] 200 /\n[OK] 200 /route\n[OK] 200 /route\n", 'Correct responses logged';
    is (slurp 'err'), "[ERROR] 500 /error\n", 'Error responses logged';

    unlink 'out'.IO;
    unlink 'err'.IO;

    $service.stop();
}

done-testing;