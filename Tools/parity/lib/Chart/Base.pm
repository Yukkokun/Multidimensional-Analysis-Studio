package Chart::Base;
sub new { my ($class, @rest) = @_; bless {}, $class }
sub add_dataset { 1 }
sub set { 1 }
sub png { 1 }
1;
