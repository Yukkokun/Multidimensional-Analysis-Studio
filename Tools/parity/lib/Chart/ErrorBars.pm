package Chart::ErrorBars;
sub new { my ($class, $w, $h) = @_; bless { w => $w, h => $h }, $class }
sub add_dataset { 1 }
sub set { 1 }
sub png {
    my ($self, $path) = @_;
    open(my $fh, '>', $path) or die "cannot write $path: $!";
    print $fh "PNG-STUB\n";
    close $fh;
    return 1;
}
1;
