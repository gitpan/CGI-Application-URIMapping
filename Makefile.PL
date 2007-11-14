use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'CGI::Application::URIMapping',
    VERSION_FROM  => 'lib/CGI/Application/URIMapping.pm',
    PREREQ_PM     => {
        CGI::Application::Dispatch => 0,
        List::MoreUtils            => 0,
    },
    ABSTRACT_FROM => 'lib/CGI/Application/URIMapping.pm',
    AUTHOR        => 'Kazuho Oku',
);
