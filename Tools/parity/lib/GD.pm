package GD;
sub import { }
1;

package GD::Image;
sub new { my ($class, $data) = @_; bless { data => $data }, $class }
sub colorAllocate { 1 }
sub string { 1 }
sub png { return "" }
1;
