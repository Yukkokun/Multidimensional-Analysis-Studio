package Win32::GUI;
sub import { }
1;

package Win32::GUI::Window;
sub new { my ($class, %args) = @_; bless { %args }, $class }
sub AddLabel        { Win32::GUI::Label->new(@_) }
sub AddProgressBar  { Win32::GUI::ProgressBar->new(@_) }
sub AddRadioButton  { Win32::GUI::RadioButton->new(@_) }
sub AddButton       { Win32::GUI::Button->new(@_) }
sub Show   { 1 }
sub Hide   { 1 }
sub DoModal { 1 }
sub SetIcon { 1 }
1;

package Win32::GUI::Label;
sub new { my ($class, %args) = @_; bless { %args }, $class }
sub Change { 1 }
1;

package Win32::GUI::Button;
sub new { my ($class, %args) = @_; bless { %args }, $class }
sub SetImage { 1 }
1;

package Win32::GUI::ProgressBar;
sub new { my ($class, %args) = @_; bless { %args }, $class }
sub SetRange { 1 }
sub DeltaPos { 1 }
sub SetPos   { 1 }
1;

package Win32::GUI::RadioButton;
sub new { my ($class, %args) = @_; bless { %args }, $class }
sub GetCheck { my $self = shift; return $self->{checked} ? 1 : 0 }
1;
