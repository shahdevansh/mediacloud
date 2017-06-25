#!/usr/bin/perl
#
# Some test strings copied from Wikipedia (CC-BY-SA, http://creativecommons.org/licenses/by-sa/3.0/).
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 16;
use utf8;

use MediaWords::Languages::ru;
use Data::Dumper;

sub test_stopwords()
{
    my $lang = MediaWords::Languages::ru->new();

    ok( $lang->get_stop_words(), 'lang_en_get_stop_words' );

    # Stop words
    my $stop_words_ru = $lang->get_stop_words();
    ok( scalar( keys( %{ $stop_words_ru } ) ) >= 140, "stop words (ru) count is correct" );

    is( $stop_words_ru->{ 'и' }, 1, "Russian test #1" );
    is( $stop_words_ru->{ 'я' }, 1, "Russian test #2" );

    # Stop word stems
    my $stop_word_stems_ru = $lang->get_stop_word_stems();
    ok( scalar( keys( %{ $stop_word_stems_ru } ) ) >= 108, "stop word stem (ru) count is correct" );
}

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::ru->new();

    #
    # Simple paragraph + some non-breakable abbreviations
    #
    $test_string = <<'QUOTE';
Новозеландцы пять раз признавались командой года по версии IRB и являются лидером по количеству набранных
очков и единственным коллективом в международном регби, имеющим положительный баланс встреч со всеми своими
соперниками. «Олл Блэкс» удерживали первую строчку в рейтинге сборных Международного совета регби дольше,
чем все остальные команды вместе взятые. За последние сто лет новозеландцы уступали лишь шести национальным
командам (Австралия, Англия, Родезия, Уэльс, Франция и ЮАР). Также в своём активе победу над «чёрными» имеют
сборная Британских островов (англ.)русск. и сборная мира (англ.)русск., которые не являются официальными
членами IRB. Более 75 % матчей сборной с 1903 года завершались победой «Олл Блэкс» — по этому показателю
национальная команда превосходит все остальные.
QUOTE

    $expected_sentences = [
'Новозеландцы пять раз признавались командой года по версии IRB и являются лидером по количеству набранных очков и единственным коллективом в международном регби, имеющим положительный баланс встреч со всеми своими соперниками.',
'«Олл Блэкс» удерживали первую строчку в рейтинге сборных Международного совета регби дольше, чем все остальные команды вместе взятые.',
'За последние сто лет новозеландцы уступали лишь шести национальным командам (Австралия, Англия, Родезия, Уэльс, Франция и ЮАР).',
'Также в своём активе победу над «чёрными» имеют сборная Британских островов (англ.)русск. и сборная мира (англ.)русск., которые не являются официальными членами IRB.',
'Более 75 % матчей сборной с 1903 года завершались победой «Олл Блэкс» — по этому показателю национальная команда превосходит все остальные.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("в т. ч.")
    #
    $test_string = <<'QUOTE';
Топоры, в т. ч. транше и шлифованные. Дания.
QUOTE

    $expected_sentences = [ 'Топоры, в т. ч. транше и шлифованные.', 'Дания.' ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Abbreviation ("род.")
    #
    $test_string = <<'QUOTE';
Влади́мир Влади́мирович Пу́тин (род. 7 октября 1952, Ленинград) — российский государственный
и политический деятель; действующий (четвёртый) президент Российской Федерации с 7 мая 2012
года. Председатель Совета министров Союзного государства (с 2008 года). Второй президент
Российской Федерации с 7 мая 2000 года по 7 мая 2008 года (после отставки президента Бориса
Ельцина исполнял его обязанности с 31 декабря 1999 по 7 мая 2000 года).
QUOTE

    $expected_sentences = [
'Влади́мир Влади́мирович Пу́тин (род. 7 октября 1952, Ленинград) — российский государственный и политический деятель; действующий (четвёртый) президент Российской Федерации с 7 мая 2012 года.',
'Председатель Совета министров Союзного государства (с 2008 года).',
'Второй президент Российской Федерации с 7 мая 2000 года по 7 мая 2008 года (после отставки президента Бориса Ельцина исполнял его обязанности с 31 декабря 1999 по 7 мая 2000 года).'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Name abbreviations
    #
    $test_string = <<'QUOTE';
Впоследствии многие из тех, кто вместе с В. Путиным работал в мэрии Санкт-Петербурга (И. И.
Сечин, Д. А. Медведев, В. А. Зубков, А. Л. Кудрин, А. Б. Миллер, Г. О. Греф, Д. Н. Козак,
В. П. Иванов, С. Е. Нарышкин, В. Л. Мутко и др.) в 2000-е годы заняли ответственные посты
в правительстве России, администрации президента России и руководстве госкомпаний.
QUOTE

    $expected_sentences = [
'Впоследствии многие из тех, кто вместе с В. Путиным работал в мэрии Санкт-Петербурга (И. И. Сечин, Д. А. Медведев, В. А. Зубков, А. Л. Кудрин, А. Б. Миллер, Г. О. Греф, Д. Н. Козак, В. П. Иванов, С. Е. Нарышкин, В. Л. Мутко и др.) в 2000-е годы заняли ответственные посты в правительстве России, администрации президента России и руководстве госкомпаний.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Date ("19.04.1953")
    #
    $test_string = <<'QUOTE';
Род Моргенстейн (англ. Rod Morgenstein, род. 19.04.1953, Нью-Йорк) — американский барабанщик,
педагог. Он известен по работе с хеви-метал группой конца 80-х Winger и джаз-фьюжн группой
Dixie Dregs. Участвовал в сессионной работе с группами Fiona, Platypus и The Jelly Jam. В
настоящее время он профессор музыкального колледжа Беркли, преподаёт ударные инструменты.
QUOTE

    $expected_sentences = [
'Род Моргенстейн (англ. Rod Morgenstein, род. 19.04.1953, Нью-Йорк) — американский барабанщик, педагог.',
'Он известен по работе с хеви-метал группой конца 80-х Winger и джаз-фьюжн группой Dixie Dregs.',
        'Участвовал в сессионной работе с группами Fiona, Platypus и The Jelly Jam.',
'В настоящее время он профессор музыкального колледжа Беркли, преподаёт ударные инструменты.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }
}

sub test_tokenize()
{
    my $lang = MediaWords::Languages::ru->new();

    #
    # Word tokenizer
    #
    my $test_string = <<'QUOTE';
Род Моргенстейн (англ. Rod Morgenstein, род. 19.04.1953, Нью-Йорк) —
американский барабанщик, педагог. Он известен по работе с хеви-метал группой
конца 80-х Winger и джаз-фьюжн группой Dixie Dregs.
QUOTE

    my $expected_words = [
        qw/
          род
          моргенстейн
          англ
          rod
          morgenstein
          род
          19
          04
          1953
          нью-йорк
          американский
          барабанщик
          педагог
          он
          известен
          по
          работе
          с
          хеви-метал
          группой
          конца
          80-х
          winger
          и
          джаз-фьюжн
          группой
          dixie
          dregs/
    ];

    {
        is( join( '||', @{ $lang->tokenize( $test_string ) } ), join( '||', @{ $expected_words } ), "tokenize" );
    }
}

sub test_stem()
{
    my $lang = MediaWords::Languages::ru->new();

    # from http://ru.wikipedia.org/
    my $stemmer_test_ru_text = <<'__END_TEST_CASE__';
        Сте́мминг — это процесс нахождения основы слова для заданного исходного слова. Основа слова необязательно
        совпадает с морфологическим корнем слова. Алгоритм стемминга представляет собой давнюю проблему в области
        компьютерных наук. Первый документ по этому вопросу был опубликован в 1968 году. Данный процесс применяется
        в поиcковых системах для обобщения поискового запроса пользователя.
__END_TEST_CASE__

    ok( utf8::is_utf8( $stemmer_test_ru_text ), "is_utf8" );

    my @split_words = @{ $lang->tokenize( $stemmer_test_ru_text ) };

    utf8::upgrade( $stemmer_test_ru_text );

    my $temp = $stemmer_test_ru_text;

    @split_words = @{ $lang->tokenize( $temp ) };

    my $lingua_stem = Lingua::Stem::Snowball->new( lang => 'ru', encoding => 'UTF-8' );

    my $lingua_stem_result = [ ( $lingua_stem->stem( \@split_words ) ) ];
    my $mw_stem_result = $lang->stem( @split_words );

    is_deeply( ( join "_", @{ $mw_stem_result } ), ( join "_", @{ $lingua_stem_result } ), "Stemmer compare test" );

    is( $mw_stem_result->[ 0 ], lc $split_words[ 0 ], "first word" );

    isnt(
        join( "_", @$mw_stem_result ),
        join( "_", @{ $lang->tokenize( lc $stemmer_test_ru_text ) } ),
        "Stemmer compare with no stemming test"
    );
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_stopwords();
    test_get_sentences();
    test_tokenize();
    test_stem();
}

main();
