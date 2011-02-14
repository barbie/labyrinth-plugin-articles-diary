package Labyrinth::Plugin::Articles::Diary;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = '1.01';

=head1 NAME

Labyrinth::Plugin::Articles::Diary - Diary plugin for Labyrinth framework

=head1 DESCRIPTION

Contains all the diary handling functionality for Labyrinth.

=cut

# -------------------------------------
# Library Modules

use base qw(Labyrinth::Plugin::Articles);

use Clone qw(clone);
use Time::Local;
#use Data::Dumper;

use Labyrinth::Audit;
use Labyrinth::DBUtils;
use Labyrinth::DTUtils;
use Labyrinth::Globals;
use Labyrinth::IPAddr;
use Labyrinth::Metadata;
use Labyrinth::MLUtils;
use Labyrinth::Session;
use Labyrinth::Support;
use Labyrinth::Variables;
use Labyrinth::Writer;

# -------------------------------------
# Variables

# type: 0 = optional, 1 = mandatory
# html: 0 = none, 1 = text, 2 = textarea

my %fields = (
    articleid   => { type => 0, html => 0 },
    quickname   => { type => 1, html => 0 },
    title       => { type => 1, html => 1 },
);

my (@mandatory,@allfields);
for(keys %fields) {
    push @mandatory, $_     if($fields{$_}->{type});
    push @allfields, $_;
}

my $LEVEL       = ADMIN;
my $SECTIONID   = 6;

my %cfields = (
    articleid   => { type => 0, html => 0 },
    commentid   => { type => 0, html => 0 },
    subject     => { type => 0, html => 1 },
    body        => { type => 1, html => 3 },
    author      => { type => 1, html => 1 },
    href        => { type => 0, html => 1 },
    publish     => { type => 0, html => 0 },
);

my (@cmandatory,@callfields);
for(keys %cfields) {
    push @cmandatory, $_        if($cfields{$_}->{type});
    push @callfields, $_;
}

my ($BLOCK,$ALLOW) = (1,2);

# -------------------------------------
# Public Methods

=head1 PUBLIC INTERFACE METHODS

=over 4

=item Archive

=item List

=item Meta

=item Cloud

=item Search

=item Item

=item Comment

=item LatestComments

=item Posted

=back

=cut

sub Archive {
    my $oldid = $cgiparams{sectionid};
    $cgiparams{sectionid} = $SECTIONID;
    $cgiparams{section} = 'diary';

    shift->SUPER::Archive();
    $tvars{articles} = undef;
    $cgiparams{sectionid} = $oldid; # reset
}

sub List {
    $cgiparams{sectionid}          = $SECTIONID;
    $settings{data}{article_limit} = $settings{diary_limit};
    $settings{data}{article_stop}  = $settings{diary_stop};

    if($cgiparams{volume}) {
        $settings{where} = 'createdate > ' . _vol2date($cgiparams{volume}) .
                      ' AND createdate < ' . _vol2date($cgiparams{volume} + 1);
    }

    shift->SUPER::List();
    _count_comments();

    # see if we can do next and previous
    my $this = 0;
    if($cgiparams{volume}) {
        for my $vol (@{$tvars{archive}{diary}}) {
            if($cgiparams{volume} == $vol->{volumeid}) {
                $this = 1;
            } else {
                $tvars{archive}{volumes}{prev} = $vol   if(!$this);
                $tvars{archive}{volumes}{next} ||= $vol if($this);
            }
        }
    }
}

sub Meta {
    return  unless($cgiparams{data});

    my $oldid = $cgiparams{sectionid};
    $cgiparams{sectionid}          = $SECTIONID;
    $settings{data}{article_limit} = $settings{diary_limit};
    $settings{data}{article_stop}  = $settings{diary_stop};

    shift->SUPER::Meta();
    _count_comments();
    $cgiparams{sectionid} = $oldid; # reset
}

sub Cloud {
    my $oldid = $cgiparams{sectionid};
    $cgiparams{sectionid} = $SECTIONID;
    $cgiparams{actcode} = 'diary-meta';
    shift->SUPER::Cloud();
    $cgiparams{sectionid} = $oldid; # reset
}

sub Search {
    return  unless($cgiparams{data});

    my $oldid = $cgiparams{sectionid};
    $cgiparams{sectionid}          = $SECTIONID;
    $settings{data}{article_limit} = $settings{diary_limit};
    $settings{data}{article_stop}  = $settings{diary_stop};

    shift->SUPER::Search();
    _count_comments();
    $cgiparams{sectionid} = $oldid; # reset
}

sub Item {
    my $oldid = $cgiparams{sectionid};
    $cgiparams{sectionid} = $SECTIONID;
    shift->SUPER::Item();
    $tvars{diary} = $tvars{article};
    my @rows = $dbi->GetQuery('hash','GetDiaryComments',$tvars{diary}->{data}->{articleid});
    for(@rows) {
        $_->{postdate} = formatDate(6,$_->{createdate});
    }

    $tvars{comments} = \@rows;
    $cgiparams{sectionid} = $oldid; # reset
}

sub Comment {
    my $check = CheckIP();
    if(    $check == $BLOCK
        || $cgiparams{typekey}
        || !$cgiparams{loopback}
        || $cgiparams{loopback} ne $settings{ipaddr}) {

        $tvars{thanks} = 3;
#        print STDERR "COMMENT SPAM ALERT:\n" . Dumper(\%cgiparams);
        return;
    }

    $cgiparams{publish} = $check == $ALLOW ? 3 : 2;

    for(keys %cfields) {
        next    unless($cfields{$_});
           if($cfields{$_}->{html} == 1)    { $cgiparams{$_} = CleanHTML($cgiparams{$_}) }
        elsif($cfields{$_}->{html} == 2)    { $cgiparams{$_} = CleanTags($cgiparams{$_}) }
        elsif($cfields{$_}->{html} == 3)    { $cgiparams{$_} = CleanTags($cgiparams{$_}) }
    }

    return  if FieldCheck(\@callfields,\@cmandatory);

    if($tvars{data}->{subject} eq 'ARRAY(0x84fb748)') {
#        print STDERR "COMMENT SPAM ALERT:\n" . Dumper(\%cgiparams);
        $tvars{thanks} = 3;
        return;
    }

    my @fields = (  $tvars{data}->{articleid},
                    $tvars{data}->{subject},
                    formatDate(),               # create date
                    $tvars{data}->{body},
                    $tvars{data}->{author},
                    $tvars{data}->{href},
                    $tvars{data}->{publish},
                    $settings{ipaddr}
    );

    $dbi->IDQuery('AddComment',@fields);
    $tvars{thanks} = $check == $ALLOW ? 2 : 1;
}

sub LatestComments {
    my @rows = $dbi->GetQuery('hash','GetCommentsLatest');
    $tvars{latest}->{comments} = \@rows;
}

sub Posted {
    return    unless $cgiparams{'userid'};
    my @rows = $dbi->GetQuery('array','CountPosts',$cgiparams{'userid'});
    $tvars{data}{posts} = @rows ? $rows[0]->[0] : 0;
}

# -------------------------------------
# Admin Methods

=head1 ADMIN INTERFACE METHODS

=over 4

=item Access

=item Admin

=item Add

=item Edit

=item Save

=item Delete

=item ListComment

=item EditComment

=item SaveComment

=item MarkIP

=item PromoteComment

=item DeleteComment

=back

=cut

sub Access  { Authorised($LEVEL) }

sub Admin {
    return  unless AccessUser($LEVEL);
    $cgiparams{sectionid} = $SECTIONID;
    shift->SUPER::Admin();
}

sub Add {
    return  unless AccessUser($LEVEL);
    $cgiparams{sectionid} = $SECTIONID;
    my $self = shift;
    $self->SUPER::Add();
    $self->SUPER::Tags();
}

sub Edit {
    return  unless AccessUser($LEVEL);
    $cgiparams{sectionid} = $SECTIONID;

    my $self = shift;
    $self->SUPER::Edit();
    $self->SUPER::Tags();
    my @rows = $dbi->GetQuery('hash','GetDiaryComments',$tvars{article}->{data}->{articleid});
    for(@rows) {
        $_->{postdate} = formatDate(6,$_->{createdate});
    }

    $tvars{articles}->{$tvars{primary}}->{data}{comments} = scalar(@rows);
    $tvars{comments} = \@rows   if(@rows);
}

sub Save {
    return  unless AccessUser($LEVEL);
    $cgiparams{sectionid} = $SECTIONID;
    $cgiparams{quickname} = formatDate(0);
    shift->SUPER::Save();
}

sub Delete {
    return  unless AccessUser($LEVEL);
    $cgiparams{sectionid} = $SECTIONID;
    shift->SUPER::Delete();
}

sub ListComment {
    return  unless AccessUser($LEVEL);
    my @rows = $dbi->GetQuery('hash','GetAdminComments');
    for(@rows) {
        $_->{postdate} = formatDate(17,$_->{createdate});
    }

    $tvars{comments} = \@rows;
    $tvars{comcount} = scalar @rows;
}

sub EditComment {
    return  unless AuthorCheck('GetCommentByID','commentid',$LEVEL);
    $tvars{comment} = $tvars{data};
    $tvars{comment}->{postdate}  = formatDate(17,$tvars{comment}->{createdate});
    $tvars{comment}->{ddpublish} = PublishSelect($tvars{comment}->{publish});
}

sub SaveComment {
    return  unless AuthorCheck('GetCommentByID','commentid',$LEVEL);
    for(keys %cfields) {
        next    unless($cfields{$_});
           if($cfields{$_}->{html} == 1)    { $cgiparams{$_} = CleanHTML($cgiparams{$_}) }
        elsif($cfields{$_}->{html} == 2)    { $cgiparams{$_} = CleanTags($cgiparams{$_}) }
        elsif($cfields{$_}->{html} == 3)    { $cgiparams{$_} = CleanTags($cgiparams{$_}) }
    }

    return  if FieldCheck(\@callfields,\@cmandatory);

    my @fields = (  $tvars{data}->{subject},
                    $tvars{data}->{body},
                    $tvars{data}->{author},
                    $tvars{data}->{href},
                    $tvars{data}->{publish},
                    $tvars{data}->{commentid}
    );

    $dbi->IDQuery('SaveComment',@fields);
}

sub MarkIP {
    return  unless AuthorCheck('GetCommentByID','commentid',$LEVEL);
    return  unless $cgiparams{mark};
    my $mark = $cgiparams{mark} eq 'allow' ? 2 : 1;

    if($mark == 2)  { AllowIP($tvars{data}->{author},$tvars{data}->{ipaddr}) }
    else            { BlockIP($tvars{data}->{author},$tvars{data}->{ipaddr}) }

    my @rows = $dbi->GetQuery('hash','GetAdminCommentByIP',$tvars{data}->{ipaddr});
    for my $row (@rows) {
        next    unless($row->{ipaddr} eq $tvars{data}->{ipaddr});
        if($mark == 2) {
            $dbi->DoQuery('PromoteComment',$tvars{data}->{publish}+1,$row->{'commentid'});
        } else {
            $dbi->DoQuery('DeleteComment',$row->{'commentid'});
        }
    }
}

sub PromoteComment {
    return  unless AuthorCheck('GetCommentByID','commentid',$LEVEL);
    $dbi->DoQuery('PromoteComment',$tvars{data}->{publish}+1,$cgiparams{'commentid'});
}

sub DeleteComment {
    return  unless AuthorCheck('GetCommentByID','commentid',$LEVEL);
    $dbi->DoQuery('DeleteComment',$cgiparams{'commentid'});
}

# -------------------------------------
# Private Methods

sub _count_comments {
    return  unless($tvars{articles} && scalar(keys %{$tvars{articles}}));

    my $ids = join(',', map {$_->{data}{articleid}} @{$tvars{mainarts}});
    my @rows = $dbi->GetQuery('array','CountDiaryComments',{ids => $ids});
    my %rows = map {$_->[0] => $_->[1]} @rows;
    for my $item (@{$tvars{mainarts}}) {
        $item->{comments} = $rows{$item->{data}{articleid}} || 0;
    }
}

sub _vol2date {
    my ($year,$mon) = $_[0] =~ /^(\d{4})(\d{2})/;
    if($mon == 13) { $year++;$mon=1; }
    return timegm(0,0,0,1,$mon-1,$year);
}

1;

__END__

=head1 SEE ALSO

L<Labyrinth>

=head1 AUTHOR

Barbie, <barbie@missbarbell.co.uk> for
Miss Barbell Productions, L<http://www.missbarbell.co.uk/>

=head1 COPYRIGHT & LICENSE

  Copyright (C) 2002-2011 Barbie for Miss Barbell Productions
  All Rights Reserved.

  This module is free software; you can redistribute it and/or
  modify it under the Artistic License 2.0.

=cut

