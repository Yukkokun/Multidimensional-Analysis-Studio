#!/usr/bin/env python3
"""
生成 golden 语料的 tagged/ 与 raw/ 两个目录。

tagged/<name>.txt : word_TAG 流，等价于 Stanford Tagger -textFile 的输出。
                    这是原版 Tagger_MAT.pl 的唯一输入（harness 用它替代 JVM）。
raw/<name>.txt    : 只有 surface，用于驱动原版的目录遍历与 curly_correct。

每个文件都刻意针对一条或几条规则，注释里写明它锁住了什么行为。
"""

import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")

# ─────────────────────────────────────────────────────────── 规则覆盖语料
# 约定：token 写作 word_TAG，TAG 用 PTB 标签集。

RULES = {
    # 01 被动：[PASS] vs [BYPA] 的分支（by 出现与否决定走哪条）
    "01_passive": """
        The_DT report_NN was_VBD written_VBN by_IN the_DT committee_NN ._.
        The_DT results_NNS were_VBD published_VBN in_IN two_CD journals_NNS ._.
        The_DT door_NN was_VBD opened_VBN ._.
        The_DT paper_NN has_VBZ been_VBN read_VBN by_IN many_JJ students_NNS ._.
    """,

    # 02 that 的四种身份：DEMP / DEMO / TOBJ / THATD
    "02_that": """
        That_DT is_VBZ the_DT problem_NN ._.
        That_DT book_NN is_VBZ mine_PRP ._.
        I_PRP think_VBP that_IN this_DT is_VBZ wrong_JJ ._.
        The_DT fact_NN that_IN she_PRP lied_VBD surprised_VBD us_PRP ._.
        The_DT book_NN that_IN I_PRP bought_VBD was_VBD expensive_JJ ._.
        He_PRP said_VBD that_IN the_DT plan_NN would_MD fail_VB ._.
    """,

    # 03 关系从句：WHSUB / WHOBJ / [SERE] / [PIRE]
    "03_wh": """
        The_DT man_NN who_WP came_VBD late_RB left_VBD ._.
        The_DT book_NN which_WDT I_PRP read_VBD was_VBD good_JJ ._.
        The_DT thing_NN which_WDT happened_VBD was_VBD odd_JJ ._.
        He_PRP arrived_VBD ,_, which_WDT was_VBD lucky_JJ ._.
        The_DT city_NN in_IN which_WDT she_PRP lives_VBZ ._.
    """,

    # 04 缩写与否定：n't→XX0、's/'re→$be、'll/'d→PRMD、[CONT]
    "04_contraction": """
        I_PRP do_VBP n't_RB know_VB ._.
        They_PRP do_VBP n't_RB want_VB to_TO go_VB ._.
        She_PRP 's_VBZ not_RB happy_JJ ._.
        We_PRP 're_VBP going_VBG to_TO win_VB ._.
        It_PRP 's_VBZ a_DT good_JJ idea_NN ._.
        He_PRP 'll_MD come_VB later_RB ._.
        I_PRP 'd_MD rather_RB stay_VB ._.
    """,

    # 05 词表类：[PUBV] [PRIV] [SUAV] [SMP] + AMP / DWNT
    "05_lexicon": """
        The_DT author_NN claims_VBZ that_IN the_DT data_NNS show_VBP a_DT trend_NN ._.
        We_PRP believe_VBP this_DT is_VBZ correct_JJ ._.
        They_PRP suggest_VBP another_DT approach_NN ._.
        The_DT results_NNS seem_VBP to_TO confirm_VB it_PRP ._.
        She_PRP appeared_VBD tired_JJ ._.
        It_PRP is_VBZ very_RB good_JJ ._.
        The_DT effect_NN was_VBD almost_RB significant_JJ ._.
    """,

    # 06 派生标签：NOMZ（-tion/-ment/-ness/-ity）、GER（-ing + 长度阈值 ≥10 字符）
    "06_nominalization": """
        The_DT implementation_NN of_IN the_DT system_NN requires_VBZ careful_JJ consideration_NN ._.
        The_DT meeting_NN was_VBD long_JJ ._.
        Understanding_NN the_DT problem_NN is_VBZ important_JJ ._.
        The_DT happiness_NN of_IN others_NNS matters_VBZ ._.
        The_DT findings_NNS are_VBP clear_JJ ._.
    """,

    # 07 介词：on→PIN、to→PIN（P1 双词模式）、[STPR]、[SPIN]
    "07_preposition": """
        The_DT book_NN is_VBZ on_IN the_DT table_NN ._.
        He_PRP walked_VBD to_TO the_DT store_NN ._.
        She_PRP went_VBD to_IN school_NN ._.
        The_DT house_NN he_PRP lives_VBZ in_IN ._.
        The_DT plan_NN is_VBZ to_TO really_RB improve_VB things_NNS ._.
    """,

    # 08 句首是 to：P1 在 j=0 的行为
    "08_start_to": """
        To_TO begin_VB ,_, the_DT data_NN are_VBP noisy_JJ ._.
        To_TO be_VB honest_JJ ,_, it_PRP failed_VBD ._.
    """,

    # 09 负索引回绕：文档倒数第二个 token 是 there_EX，
    #    于是在 j=0 处 $word[$j-2] 回绕到 there_EX，BEMA 的守卫条件被打破。
    #    不做回绕的实现会在这里多出一个 [BEMA]，golden 会立刻发现。
    "09_negative_index": """
        Was_VBD the_DT report_NN finished_VBN ?_.
        The_DT papers_NNS were_VBD there_EX by_IN
    """,

    # 10 量化词/不定代词：INPR 被 QUPR 覆盖（everybody/something），只有 nobody 留下 INPR
    "10_quantifier": """
        Each_DT student_NN brought_VBD something_NN ._.
        Everybody_PRP knows_VBZ that_IN ._.
        Nobody_PRP came_VBD ._.
        Some_DT people_NNS left_VBD early_RB ._.
    """,

    # 11 短语并列 PHC 与独立子句并列 ANDC
    "11_coordination": """
        The_DT plan_NN ,_, and_IN the_DT budget_NN ,_, and_IN the_DT scope_NN were_VBD approved_VBN ._.
        He_PRP ran_VBD fast_RB and_IN far_RB ._.
        The_DT red_JJ and_IN blue_JJ flags_NNS ._.
    """,

    # 12 短文本：tokens < 400，触发 TTR 的 undef 缺陷（distinct + 1）
    "12_short": """
        A_DT small_JJ corpus_NN is_VBZ useful_JJ ._.
        It_PRP tests_VBZ the_DT short_JJ path_NN ._.
    """,
}



# ─────────────────────────────────────────────────────────── 第二批：补齐 19 个未覆盖特征
# 每个文件开头都放一句「垫场句」，让后续句首 token 的 $word[$j-1] 落在标点上
# （否则 j=0 会触发负索引回绕，测的就不是本条规则了）。

RULES2 = {
    # DPAR：标点后的小品词
    "01_particle": """
        The_DT test_NN starts_VBZ here_RB ._.
        Well_UH ,_, I_PRP think_VBP it_PRP works_VBZ ._.
        Anyhow_RB ,_, we_PRP tried_VBD ._.
    """,

    # CAUS / CONC / COND / OSUB：四个从属连词
    "02_subordinator": """
        The_DT test_NN starts_VBZ here_RB ._.
        He_PRP left_VBD because_IN it_PRP rained_VBD ._.
        Although_IN it_PRP rained_VBD ,_, we_PRP went_VBD ._.
        If_IN it_PRP rains_VBZ ,_, we_PRP stay_VBP ._.
        Since_IN it_PRP rained_VBD ,_, we_PRP stayed_VBD ._.
    """,

    # POMD / NEMD：情态动词三类
    "03_modal": """
        The_DT test_NN starts_VBZ here_RB ._.
        It_PRP may_MD rain_VB ._.
        You_PRP should_MD go_VB ._.
        They_PRP must_MD wait_VB ._.
        He_PRP ought_MD to_TO try_VB ._.
    """,

    # [PRESP] / [PASTP] / [WZPRES] / [WZPAST]：四种分词结构
    "04_participle": """
        The_DT test_NN starts_VBZ here_RB ._.
        Walking_VBG home_RB ,_, she_PRP saw_VBD it_PRP ._.
        Written_VBN carefully_RB ,_, the_DT report_NN was_VBD good_JJ ._.
        The_DT man_NN walking_VBG home_RB waved_VBD ._.
        The_DT report_NN written_VBN carefully_RB was_VBD long_JJ ._.
    """,

    # [WHCL] / [WHQU] / TSUB / THAC / [PROD]
    "05_clause": """
        The_DT test_NN starts_VBZ here_RB ._.
        He_PRP asked_VBD what_WP happened_VBD ._.
        What_WP did_VBD you_PRP say_VB ?_.
        The_DT claim_NN that_IN matters_VBZ is_VBZ odd_JJ ._.
        It_PRP is_VBZ clear_JJ that_IN he_PRP lied_VBD ._.
        She_PRP runs_VBZ faster_RBR than_IN I_PRP do_VBP ._.
    """,

    # SYNE / SPP2
    "06_negation": """
        The_DT test_NN starts_VBZ here_RB ._.
        No_DT solution_NN exists_VBZ ._.
        Neither_DT option_NN works_VBZ ._.
        Nor_DT do_VBP we_PRP care_VB ._.
        You_PRP should_MD read_VB this_DT ._.
    """,

    # HDG：maybe / at about / sort of
    "07_hedge": """
        The_DT test_NN starts_VBZ here_RB ._.
        Maybe_RB it_PRP works_VBZ ._.
        He_PRP left_VBD at_IN about_RB noon_NN ._.
        They_PRP sort_NN of_IN agree_VBP ._.
    """,
}


# ─────────────────────────────────────────────────────────── 第三批：补齐 RuleTable §4 列的 10 条裸路径
# 这些句子的英文都不太自然——目标是覆盖规则分支，不是语料质量。
# 关键技巧：`that` 后面必须避开 TSUB(515) 和 TOBJ(528) 的触发集，
# 否则 THVC 会被后执行的 TSUB/TOBJ 覆盖掉，测的就不是 THVC 了。

RULES3 = {
    # THVC 的长距离变体：P3.36(j-4) / P3.37(j-5) / P3.38(j-6)
    "01_thvc_long": """
        The_DT test_NN starts_VBZ here_RB ._.
        He_PRP said_VBD in_IN the_DT report_NN that_IN perhaps_RB not_RB everyone_QUPR agrees_VBZ ._.
        He_PRP said_VBD in_IN the_DT big_JJ report_NN that_IN perhaps_RB not_RB everyone_QUPR agrees_VBZ ._.
        He_PRP said_VBD in_IN the_DT big_JJ new_JJ report_NN that_IN perhaps_RB not_RB everyone_QUPR agrees_VBZ ._.
    """,

    # CONJ 的多词模式：P3.11(两词) P3.12(三词) P3.13(四词)
    "02_conjunct_multiword": """
        The_DT test_NN starts_VBZ here_RB ._.
        In_IN other_JJ words_NNS ,_, it_PRP failed_VBD ._.
        For_IN example_NN ,_, we_PRP tried_VBD ._.
        On_IN the_DT other_JJ hand_NN ,_, it_PRP worked_VBD ._.
        In_IN comparison_NN ,_, the_DT effect_NN was_VBD small_JJ ._.
    """,

    # EMPH 的三个多词分支 P3.16 + P3.55(more or less) + P3.32(soon) + P3.28 第二支
    "03_emphatic": """
        The_DT test_NN starts_VBZ here_RB ._.
        He_PRP did_VBD it_PRP for_IN sure_JJ ._.
        We_PRP need_VBP a_DT lot_NN of_IN time_NN ._.
        It_PRP was_VBD such_JJ a_DT mess_NN ._.
        It_PRP is_VBZ more_RBR or_CC less_RBR fixed_JJ ._.
        He_PRP left_VBD soon_RB ._.
        He_PRP tried_VBD to_TO really_RB quickly_RB improve_VB it_PRP ._.
    """,

    # WHQU 的另外四支：P3.19 分支 1(MD) / 3(have) / 4(be) / 5(隔一词)
    "04_wh_aux": """
        The_DT test_NN starts_VBZ here_RB ._.
        How_WRB could_MD it_PRP work_VB ?_.
        What_WP have_VBP they_PRP done_VBN ?_.
        Why_WRB is_VBZ it_PRP so_RB ?_.
        It_PRP is_VBZ true_JJ ._. So_RB what_WP is_VBZ the_DT point_NN ?_.
    """,

    # P3.8：PRED + PHC + JJ 的连锁；P1.1 的 WDT 分支 + PIRE
    "05_chain": """
        The_DT test_NN starts_VBZ here_RB ._.
        The_DT result_NN is_VBZ good_JJ and_IN bad_JJ ._.
        The_DT extent_NN to_TO which_WDT it_PRP matters_VBZ is_VBZ unclear_JJ ._.
    """,
}

# ─────────────────────────────────────────────────────────── 长文本（TTR 窗口满）
NOUNS = ["system", "method", "result", "analysis", "feature", "corpus", "measure",
         "pattern", "factor", "model", "sample", "variable", "context", "function"]
ADJS = ["important", "general", "possible", "similar", "recent", "clear", "complex",
        "different", "available", "significant"]
VERBS = ["show", "suggest", "indicate", "require", "provide", "describe", "compare"]
ADVS = ["also", "often", "however", "therefore", "still", "already"]


def bulk_tokens(target, seed):
    """用模板循环生成 target 个 token 的 word_TAG 流（确定性）。"""
    rng = random.Random(seed)
    out = []
    while len(out) < target:
        n, a, v = rng.choice(NOUNS), rng.choice(ADJS), rng.choice(VERBS)
        n2, a2 = rng.choice(NOUNS), rng.choice(ADJS)
        adv = rng.choice(ADVS)
        out += [
            "The_DT", f"{a}_JJ", f"{n}_NN", f"{adv}_RB", f"{v}_VBZ", "the_DT",
            f"{a2}_JJ", f"{n2}_NN", "._.",
            "This_DT", f"{n}_NN", "was_VBD", f"{v[:-1]}ed_VBN", "by_IN",
            "the_DT", f"{n2}_NN", "._.",
        ]
    return out[:target]


BULK = {
    "a_120": (120, 11),
    "b_450": (470, 22),   # 470 个原始 token ≈ 415 个有效词，跨过 400 的 TTR 窗口
    "c_700": (700, 33),
}


def write_corpus(name, files):
    for sub in ("raw", "tagged"):
        os.makedirs(os.path.join(FIX, name, sub), exist_ok=True)
    for fname, tokens in files.items():
        tagged = " ".join(tokens)
        raw = " ".join(t.rsplit("_", 1)[0] for t in tokens)
        with open(os.path.join(FIX, name, "tagged", fname + ".txt"), "w") as f:
            f.write(tagged + "\n")
        with open(os.path.join(FIX, name, "raw", fname + ".txt"), "w") as f:
            f.write(raw + "\n")


def main():
    rules = {}
    for key, block in RULES.items():
        toks = block.split()
        rules[key] = toks
    write_corpus("rules", rules)
    print(f"rules: {len(rules)} files, {sum(len(v) for v in rules.values())} tokens")

    rules2 = {k: v.split() for k, v in RULES2.items()}
    write_corpus("rules2", rules2)
    print(f"rules2: {len(rules2)} files, {sum(len(v) for v in rules2.values())} tokens")

    rules3 = {k: v.split() for k, v in RULES3.items()}
    write_corpus("rules3", rules3)
    print(f"rules3: {len(rules3)} files, {sum(len(v) for v in rules3.values())} tokens")

    bulk = {}
    for key, (n, seed) in BULK.items():
        bulk[key] = bulk_tokens(n, seed)
    write_corpus("bulk", bulk)
    print(f"bulk: {len(bulk)} files, {sum(len(v) for v in bulk.values())} tokens")


if __name__ == "__main__":
    sys.exit(main())
