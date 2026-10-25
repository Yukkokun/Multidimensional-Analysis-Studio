#!/usr/bin/perl
#
# extract-constants.pl —— 从原版 Perl 源码抽取所有数值常量与词表，生成 JSON。
#
# 目的：Swift 侧永远不手抄常量。原版改一行，重跑本脚本即可。
#
# 输出（默认 Tools/parity/generated/）：
#   biber-features.json     65 个特征的 id 与类型（tag / bracket）
#   zscore-tables.json      67 组 mean / sd（65 特征 + AWL + TTR）
#   texttype-centroids.json 8 个 Biber(1989) 文本类型质心（D1–D5）
#   genre-centroids.json    8 个 Biber(1988) 体裁质心（D1–D6）+ 误差带上下界
#   lexicons.json           公共/私/劝说动词、介词、be/do/have/wh 等正则片段
#
use strict;
use warnings;
use JSON::PP;
use File::Path qw(make_path);
use File::Basename qw(dirname);
use FindBin qw($Bin);

my $ORIG = "$Bin/../../.." . '/multidimensionalanalysistagger-source code';
my $OUT  = "$Bin/../generated";
make_path($OUT);

sub slurp { my $f = shift; open(my $fh, '<', $f) or die "open $f: $!"; local $/; my $s = <$fh>; close $fh; return $s }
sub spew_json {
    my ($name, $data) = @_;
    my $json = JSON::PP->new->canonical->pretty->encode($data);
    open(my $fh, '>', "$OUT/$name") or die "write $name: $!";
    print $fh $json;
    close $fh;
    print "  $name\n";
}

my $count_only = slurp("$ORIG/count_only.pl");
my $calc       = slurp("$ORIG/calc_dimensions.pl");
my $dims_graph = slurp("$ORIG/dimensions_graph.pl");
my $tagger     = slurp("$ORIG/Tagger_MAT.pl");

# ─────────────────────────────────────────── 1. 特征清单（顺序 = 原版声明顺序）
$count_only =~ /\@biber_tags = \((.*?)\);/s or die "biber_tags not found\n";
my @raw_tags = split(/,/, $1);
my @features;
for my $t (@raw_tags) {
    $t =~ s/^\s+|\s+$//g;
    next unless length $t;
    $t =~ s/^'|'$//g;                       # 去掉 Perl 的字符串引号
    push @features, {
        id   => $t,
        kind => ($t =~ /^\[/ ? 'bracket' : 'tag'),
    };
}
die "expected 65 features, got " . scalar(@features) . "\n" unless @features == 65;

# ─────────────────────────────────────────── 2. 均值 / 标准差
my (%mean, %sd);
for my $spec ([biber_means => \%mean], [biber_sds => \%sd]) {
    my ($var, $href) = @$spec;
    $calc =~ /%$var = \((.*?)\);/s or die "$var not found\n";
    my $body = $1;
    while ($body =~ /("[^"]+"|\w+)\s*=>\s*(-?[\d.]+)/g) {
        my ($k, $v) = ($1, $2);
        $k =~ s/^"|"$//g;
        $href->{$k} = $v + 0;
    }
}
die "means size mismatch: " . scalar(keys %mean) . " vs " . scalar(keys %sd) . "\n"
    unless keys(%mean) == keys(%sd);
die "expected 67 stats, got " . scalar(keys %mean) . "\n" unless keys(%mean) == 67;

my @stats = map {
    { id => $_, mean => $mean{$_}, sd => $sd{$_} }
} sort keys %mean;                           # 排序只为 diff 稳定，消费方按 id 取值

# ─────────────────────────────────────────── 3. 文本类型质心（D1–D5）
# calc_dimensions.pl 里形如：
#   "Learned exposition" => sqrt((($dimension{"1"}{$files[$i]} - -20) ** 2) + ... )
my @text_types;
my $tt_block = $calc;
$tt_block =~ /%texttype_finder = \((.*?)\n\t*\);/s or die "texttype_finder not found\n";
my $tt_body = $1;
while ($tt_body =~ /"([^"]+)"\s*=>\s*sqrt\((.*?)\),?\s*$/gm) {
    my ($name, $expr) = ($1, $2);
    my @v;
    while ($expr =~ /\$dimension\{"(\d)"\}\{\$files\[\$i\]\}\s*-\s*(-?[\d.]+)\)\s*\*\*\s*2/g) {
        push @v, [ $1, $2 + 0 ];
    }
    next unless @v == 5;
    push @text_types, {
        id        => $name,
        dimension => [ map { $_->[1] } @v ],
    };
}
die "expected 8 text types, got " . scalar(@text_types) . "\n" unless @text_types == 8;

# ─────────────────────────────────────────── 4. 体裁质心（D1–D6）+ 误差带
my @genre_names = ("Conversations", "Broadcasts", "Prepared speeches", "Personal letters",
                   "General fiction", "Press reportage", "Academic prose", "Official documents");
my %centroid;   # dim => [8 values]
my %band;       # dim => { max => [...], min => [...] }
for my $d (1 .. 6) {
    $dims_graph =~ /\@dim$d = \(([^)]*)\);/ or die "dim$d centroid not found\n";
    my @v = map { $_ + 0 } split(/\s*,\s*/, $1);
    die "dim$d expected 8 values\n" unless @v == 8;
    $centroid{$d} = \@v;

    for my $which (qw(max min)) {
        $dims_graph =~ /\@dim${d}_$which = \(([^;]*)\);/ or die "dim${d}_$which not found\n";
        my $expr = $1;
        # 把 ($dim1[5] - -24.1) 之类的表达式求值成数字
        my @parts = split(/,/, $expr);
        my @vals;
        for my $p (@parts) {
            $p =~ s/^\s+|\s+$//g;
            next unless length $p;
            $p =~ s/\$dim$d\[(\d)\]/$centroid{$d}[$1]/ge;
            my $v = eval $p;      # 纯算术，输入受控
            die "eval failed for dim$d $which: $p ($@)\n" if $@;
            push @vals, $v + 0;
        }
        die "dim${d}_$which expected 8 values, got " . scalar(@vals) . "\n" unless @vals == 8;
        $band{$d}{$which} = \@vals;   # 注意：这是相对均值的误差偏移，不是绝对边界
    }
}

# @dimN_max / @dimN_min 是 Chart::ErrorBars 的「误差量」，语义是**距离**，不是坐标：
# 画的时候从均值向上/向下各拉这么多。数组里有正有负（例如 @dim1_min 的 -9.5），
# 但负号只是当年手写表达式留下的，画出来仍然是「向下 9.5」——
# 原版 Dimension1_GroundTruth.png 里 Prepared speeches 就是从 2.2 拉到 -7.3 与 14.8。
# 所以必须取绝对值：high = 均值 + |max|，low = 均值 - |min|。
my @genres;
for my $i (0 .. 7) {
    push @genres, {
        id        => $genre_names[$i],
        dimension => [ map { $centroid{$_}[$i] } 1 .. 6 ],
        rangeHigh => [ map { $centroid{$_}[$i] + abs($band{$_}{max}[$i]) } 1 .. 6 ],
        rangeLow  => [ map { $centroid{$_}[$i] - abs($band{$_}{min}[$i]) } 1 .. 6 ],
    };
}

# ─────────────────────────────────────────── 5. 词表与正则片段
my %lex;
for my $name (qw(public private suasive preposition be do have who wp)) {
    $tagger =~ /^\s*\$${name}\s*=\s*"(.*?)";/m or die "\$$name not found\n";
    my $raw = $1;
    if ($name =~ /^(public|private|suasive)$/) {
        my @items = grep { length } split(/\|/, $raw);
        my %seen;
        my @surfaces = grep { !$seen{$_}++ } map { s/_V$//r } @items;
        $lex{ $name } = { regex => $raw, surfaces => [ sort @surfaces ], forms => scalar(@items) };
    } else {
        $lex{ $name } = { regex => $raw };
    }
}


# ─────────────────────────────────────────── 6. 词表（按行号机械抽取，避免手抄）
# 每个词表都写在源码的某一行里，形如 \bWord_|\bOther_TAG。这里按行号定位，
# 抽出所有 \b<surface>_<tagPrefix> 并拼回一个 fragment，Swift 侧用同一套 Lexicon
# 解析器消费（surface 精确 + tag 前缀）。
my @line_lists = (
    [ time    => 443 ], [ place   => 453 ], [ amp     => 651 ], [ dwnt    => 657 ],
    [ fpp1    => 693 ], [ spp2    => 698 ], [ tpp3    => 703 ], [ pit     => 708 ],
    [ conj    => 259 ], [ conc    => 718 ], [ cond    => 723 ], [ caus    => 713 ],
    [ pomd    => 728 ], [ nemd    => 733 ], [ emph    => 287 ], [ dpar    => 580 ],
    [ hdgm    => 558 ], [ smp     => 758 ], [ andcNx  => 639 ], [ timeSub => 446 ],
);
my @src_lines = split(/\r?\n/, $tagger);
my %wordlists;
for my $spec (@line_lists) {
    my ($name, $ln) = @$spec;
    my $text = $src_lines[$ln - 1];
    die "line $ln is empty (for $name)\n" unless defined $text && length $text;
    my @frags;
    while ($text =~ /\\b([A-Za-z'.\-\\]+_[A-Za-z0-9]*)/g) { my $f = $1; $f =~ s/\\//g; push @frags, $f }
    die "no word forms found on line $ln for $name\n" unless @frags;
    $wordlists{$name} = join('|', @frags);
}

# ─────────────────────────────────────────── 输出
print "writing to $OUT\n";
spew_json("biber-features.json",     { source => "MAT 1.3.3 count_only.pl", features => \@features });
spew_json("zscore-tables.json",      { source => "MAT 1.3.3 calc_dimensions.pl", stats => \@stats });
spew_json("texttype-centroids.json", { source => "MAT 1.3.3 calc_dimensions.pl", textTypes => \@text_types });
spew_json("genre-centroids.json",    { source => "MAT 1.3.3 dimensions_graph.pl", genres => \@genres });
spew_json("lexicons.json",           { source => "MAT 1.3.3 Tagger_MAT.pl", lexicons => \%lex });
spew_json("wordlists.json",          { source => "MAT 1.3.3 Tagger_MAT.pl (按行号抽取)", lists => \%wordlists });

printf "\nfeatures=%d stats=%d texttypes=%d genres=%d\n",
    scalar(@features), scalar(@stats), scalar(@text_types), scalar(@genres);
printf "wordlists: %s\n", join(", ", map { "$_=" . scalar(split(/\|/, $wordlists{$_})) } sort keys %wordlists);
printf "lexicon surfaces: public=%d private=%d suasive=%d\n",
    scalar(@{ $lex{public}{surfaces} }), scalar(@{ $lex{private}{surfaces} }),
    scalar(@{ $lex{suasive}{surfaces} });
