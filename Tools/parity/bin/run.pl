#!/usr/bin/perl
#
# run.pl —— 在 macOS 上无 UI 运行原版 MAT 的「标注规则 + 计数 + 统计」全链路。
#
# 用途：生成 golden 输出，供 Swift 移植版做逐字节回归。
#
# 只做两处 harness 补丁（都只影响可运行性与行序，不影响任何数值）：
#   1. Tagger_MAT.pl 里的 system("java ...") 换成从 $ENV{ST_INJECT} 拷贝预制的
#      Stanford 标注结果。这样 POS 标注这个唯一外部变量被摘掉，Perl 侧和 Swift 侧
#      吃完全相同的 word_TAG 流。
#   2. readdir 结果排序。原版依赖目录遍历顺序（NTFS 恰好近似字母序，APFS 不保证），
#      不排序就无法得到可复现的 golden。
#
# 用法：
#   perl run.pl --corpus <fixtures/rules> --work <build/rules> --out <goldens/rules> [--clamp]
#
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Basename qw(basename);
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Getopt::Long;
use Cwd qw(abs_path);

# ---------------------------------------------------------------- 取整口径
#
# 原版只跑 Windows，`sprintf "%.2f"` 走 MSVCRT：遇到精确的 .5 **远离零**取整
# （-0.625 → "-0.63"、3.125 → "3.13"）。macOS 的 libc 是「向偶数取整」
# （-0.625 → "-0.62"、3.125 → "3.12"）。
#
# 这个差异不是理论问题：GroundTruth 语料上有 11 个格子踩在 .5 上，
# 用 macOS 规则会稳定差 0.01。所以 harness 必须替 Windows 说话，
# 否则 golden 描述的是「macOS 上的 Perl」，而不是「原版 MAT」。
#
# 只拦 `sprintf "%.2f", <单个标量>` 这一种形状（原版全部数值输出都是这个形状），
# 其余一律透传给系统 sprintf。
#
# ⚠️ 判定「是不是 .5」不能靠 $x*100：-1.775 的精确二进制值是
# -1.77499999999999991…，乘 100 会被舍入成 -177.5，误判成 .5。
# 必须看 30 位十进制展开：第 3 位起恰好是 5 后跟全 0 才算真 .5。
BEGIN {
    *CORE::GLOBAL::sprintf = sub {
        my ($fmt, @rest) = @_;
        if (defined $fmt && $fmt eq '%.2f' && @rest == 1 && !ref $rest[0]) {
            no warnings 'numeric';
            my $x = $rest[0];
            my $s = CORE::sprintf('%.30f', $x);
            if ($s =~ /^(-?)(\d+)\.(\d{2})(5)(0*)$/) {
                my ($sign, $ip, $keep, $five, $zeros) = ($1, $2, $3, $4, $5);
                my $val = ($ip * 100 + $keep + 1) / 100;
                $val = -$val if $sign eq '-';
                return CORE::sprintf('%.2f', $val);          # 远离零
            }
        }
        return CORE::sprintf($fmt, @rest);
    };
}

my ($corpus, $work, $out, $clamp) = ('', '', '', 0);
GetOptions(
    'corpus=s' => \$corpus,
    'work=s'   => \$work,
    'out=s'    => \$out,
    'clamp'    => \$clamp,
) or die "bad options\n";
die "need --corpus/--work/--out\n" unless $corpus && $work && $out;

my $ORIG = "$Bin/../../.." . '/multidimensionalanalysistagger-source code';
die "cannot find original source at $ORIG\n" unless -d $ORIG;

remove_tree($work);
make_path($work);
$work = abs_path($work);
my $src = "$work/src";
make_path($src);

# ---------------------------------------------------------------- 复制 + 打补丁
sub slurp { my $f = shift; open(my $fh, '<', $f) or die "open $f: $!"; local $/; my $s = <$fh>; close $fh; return $s }
sub spew  { my ($f, $s) = @_; open(my $fh, '>', $f) or die "write $f: $!"; print $fh $s; close $fh }

for my $f (qw(count_only.pl calc_dimensions.pl dimensions_graph.pl texttype_graph.pl curly_correct.pl)) {
    spew("$src/$f", slurp("$ORIG/$f"));
}

my $tag = slurp("$ORIG/Tagger_MAT.pl");

# 补丁 1：跳过 JVM
# 用 index/substr 做定点手术而不是正则：源文件是 CRLF，跨行正则容易被 \r 绊住。
#   before:  $command = "java ... -textFile ... > ...";
#            system("$command");
#   after:   system("cp", $ENV{ST_INJECT}."/".$files[$i], $directory_ST."/ST_".$files[$i]);
my $java_repl = q{			system("cp", $ENV{ST_INJECT} . "/" . $files[$i], $directory_ST . "/ST_" . $files[$i]);};
my $p1_start = index($tag, q{$command = "java});
die "patch 1 (java -> cp) failed: assignment line not found\n" if $p1_start < 0;
my $p1_end = index($tag, q{system("$command");}, $p1_start);
die "patch 1 (java -> cp) failed: 'system(\"\$command\");' not found\n" if $p1_end < 0;
$p1_end += length(q{system("$command");});
$p1_end++ while $p1_end < length($tag) && substr($tag, $p1_end, 1) =~ /[\r\n]/;
$tag = substr($tag, 0, $p1_start) . $java_repl . "\n" . substr($tag, $p1_end);

# 补丁 2：readdir 排序（两处：校验循环与 ST 循环共用第一次，MAT 循环是第二次）
my $sorted = $tag;
$sorted =~ s/\@files = readdir\(DR\);/\@files = sort readdir(DR);/g;
die "patch 2 (sort readdir in Tagger_MAT) failed\n" if $sorted eq $tag;
$tag = $sorted;
spew("$src/Tagger_MAT.pl", $tag);

my $cnt = slurp("$src/count_only.pl");
my $cnt2 = $cnt;
$cnt2 =~ s/\@files = readdir\(DR\);/\@files = sort readdir(DR);/g;
die "patch 2 (sort readdir in count_only) failed\n" if $cnt2 eq $cnt;
spew("$src/count_only.pl", $cnt2);

# ---------------------------------------------------------------- 准备语料目录
my $name = basename($corpus);
my $corpus_dir = "$work/corpus";
make_path($corpus_dir);

opendir(my $dh, "$corpus/raw") or die "no raw/ in $corpus: $!";
my @raw = sort grep { /\.txt$/i } readdir($dh);
closedir($dh);
die "no .txt in $corpus/raw\n" unless @raw;
copy("$corpus/raw/$_", "$corpus_dir/$_") or die "copy $_: $!" for @raw;

$ENV{ST_INJECT} = "$corpus/tagged";

# ---------------------------------------------------------------- 全局状态（原版在 MAT.pl 里创建）
require Win32::GUI;

our ($dir, @folders, $corpus_name, $tokens_for_ttr);
our ($status, $progress_bar, $rb_biber, $rb_all, $correction_yes, $correction_no, $prompt_window);
# dimensions_graph.pl 会读这 6 个「显示哪几张图」的复选框；golden 全部置 1，
# 保证 6 张图的代码路径都被执行到（否则某些分支的变量未初始化会掩盖问题）。
our ($dimensions_window, $db_dim1, $db_dim2, $db_dim3, $db_dim4, $db_dim5, $db_dim6);

$dir          = $corpus_dir;
@folders      = ('', $name);          # $folders[$#folders] 必须等于语料名
$corpus_name  = $name;
$tokens_for_ttr = 400;

$status        = Win32::GUI::Label->new();
$progress_bar  = Win32::GUI::ProgressBar->new();
$prompt_window = Win32::GUI::Window->new();
$dimensions_window = Win32::GUI::Window->new();
for my $slot (\$db_dim1, \$db_dim2, \$db_dim3, \$db_dim4, \$db_dim5, \$db_dim6) {
    $$slot = Win32::GUI::RadioButton->new(checked => 1);
}
$rb_biber      = Win32::GUI::RadioButton->new(checked => 1);   # 仅 VASW 标签
$rb_all        = Win32::GUI::RadioButton->new(checked => 0);
$correction_yes = Win32::GUI::RadioButton->new(checked => $clamp ? 1 : 0);
$correction_no  = Win32::GUI::RadioButton->new(checked => $clamp ? 0 : 1);

push @INC, $src;
require "$src/Tagger_MAT.pl";
require "$src/count_only.pl";

# ---------------------------------------------------------------- 跑
print "[harness] corpus=$name files=" . scalar(@raw) . " clamp=" . ($clamp ? 1 : 0) . "\n";

Tagger_MAT();
print "[harness] tagging done -> $corpus_dir/MAT_$name\n";

count_only();
print "[harness] counting done -> $corpus_dir/MAT_$name/Statistics\n";

# ---------------------------------------------------------------- 收集产物
remove_tree($out);
make_path("$out/stream");
make_path("$out/csv");

my $mat_dir = "$corpus_dir/MAT_$name";
opendir(my $mh, $mat_dir) or die "open $mat_dir: $!";
my @mats = sort grep { /_MAT\.txt$/ } readdir($mh);
closedir($mh);
copy("$mat_dir/$_", "$out/stream/$_") or die "copy $_: $!" for @mats;

opendir(my $sh, "$mat_dir/Statistics") or die "no Statistics dir: $!";
my @csv = sort grep { /\.csv$/ } readdir($sh);
closedir($sh);
copy("$mat_dir/Statistics/$_", "$out/csv/$_") or die "copy $_: $!" for @csv;

printf "[harness] wrote %d stream files, %d csv files -> %s\n", scalar(@mats), scalar(@csv), $out;
