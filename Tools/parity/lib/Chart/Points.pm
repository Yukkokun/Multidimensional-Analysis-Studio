package Chart::Points;
sub new { my ($class, $w, $h) = @_; bless { w => $w, h => $h }, $class }
sub add_dataset { 1 }
sub set { 1 }
sub scalar_png { return "" }

# texttype_graph.pl 会遍历 $imagemap_data->[1..9][0..10] 并解引用成 [x, y]
sub imagemap_dump {
    my @rows;
    for my $row (0 .. 9) {
        push @rows, [ map { [ 0, 0 ] } 0 .. 10 ];
    }
    return \@rows;
}
1;
