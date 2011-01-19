use 5.006;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME            => 'Labyrinth::Plugin::Articles::Diary',
    VERSION_FROM    => 'lib/Labyrinth/Plugin/Articles/Diary.pm',
    PREREQ_PM       => {
        'Labyrinth'                 => '5.03',
        'Labyrinth::Plugin::Core'   => '5.04',
        'Clone'                     => 0,
        'Time::Local'               => 0

    },
    NO_META     => 1,
    ABSTRACT    => 'Diary plugin for the Labyrinth framework',
    AUTHOR      => 'Barbie <barbie@cpan.org>',
);
