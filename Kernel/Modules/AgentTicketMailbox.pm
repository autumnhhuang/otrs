# --
# Kernel/Modules/AgentTicketMailbox.pm - to view all locked tickets
# Copyright (C) 2001-2007 OTRS GmbH, http://otrs.org/
# --
# $Id: AgentTicketMailbox.pm,v 1.13.2.1 2007-02-27 10:48:57 martin Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --

package Kernel::Modules::AgentTicketMailbox;

use strict;
use Kernel::System::State;

use vars qw($VERSION);
$VERSION = '$Revision: 1.13.2.1 $';
$VERSION =~ s/^\$.*:\W(.*)\W.+?$/$1/;

sub new {
    my $Type = shift;
    my %Param = @_;

    # allocate new hash for object
    my $Self = {};
    bless ($Self, $Type);

    # get common opjects
    foreach (keys %Param) {
        $Self->{$_} = $Param{$_};
    }

    # check all needed objects
    foreach (qw(ParamObject DBObject QueueObject LayoutObject ConfigObject LogObject
      UserObject)) {
        die "Got no $_" if (!$Self->{$_});
    }

    $Self->{StateObject} = Kernel::System::State->new(%Param);

    $Self->{HighlightColor2} = $Self->{ConfigObject}->Get('HighlightColor2');

    $Self->{StartHit} = $Self->{ParamObject}->GetParam(Param => 'StartHit') || 1;
    $Self->{PageShown} = $Self->{UserQueueViewShowTickets} || $Self->{ConfigObject}->Get('PreferencesGroups')->{QueueViewShownTickets}->{DataSelected} || 10;

    return $Self;
}

sub Run {
    my $Self = shift;
    my %Param = @_;
    my $Output;
    my $QueueID = $Self->{QueueID};

    my $SortBy = $Self->{ParamObject}->GetParam(Param => 'SortBy') || $Self->{ConfigObject}->Get('Ticket::Frontend::MailboxSortBy::Default') || 'Age';
    my $OrderBy = $Self->{ParamObject}->GetParam(Param => 'OrderBy') || $Self->{ConfigObject}->Get('Ticket::Frontend::MailboxOrder::Default') || 'Up';

    # store last screen
    $Self->{SessionObject}->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key => 'LastScreenView',
        Value => $Self->{RequestedURL},
    );
    # store last queue screen
    $Self->{SessionObject}->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key => 'LastScreenOverview',
        Value => $Self->{RequestedURL},
    );

    # starting with page ...
    my $Refresh = '';
    if ($Self->{UserRefreshTime}) {
        $Refresh = 60 * $Self->{UserRefreshTime};
    }
    $Output .= $Self->{LayoutObject}->Header(
        Refresh => $Refresh,
    );
    $Output .= $Self->{LayoutObject}->NavigationBar();
    my %LockedData = $Self->{TicketObject}->GetLockedCount(UserID => $Self->{UserID});

    # get locked  viewable tickets...
    my @ViewableTickets = ();
    my $SortByS = $SortBy;
    if ($SortByS eq 'CreateTime') {
        $SortByS = 'Age';
    }
    # check view type
    if (!$Self->{Subaction}) {
        $Self->{Subaction} = 'All';
    }
    if ($Self->{Subaction} eq 'Pending') {
        my @StateIDs = $Self->{StateObject}->StateGetStatesByType(
            Type => 'PendingReminder',
            Result => 'ARRAY',
        );
        push (@StateIDs, $Self->{StateObject}->StateGetStatesByType(
                Type => 'PendingAuto',
                Result => 'ARRAY',
            )
        );
        @ViewableTickets = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            Limit => 1000,
            StateIDs => \@StateIDs,
            Locks => ['lock'],
            OwnerIDs => [$Self->{UserID}],
            OrderBy => $OrderBy,
            SortBy => $SortByS,
            UserID => 1,
            Permission => 'ro',
        );
    }
    elsif ($Self->{Subaction} eq 'Reminder') {
        my @StateIDs = $Self->{StateObject}->StateGetStatesByType(
            Type => 'PendingReminder',
            Result => 'ARRAY',
        );
        @ViewableTickets = ();
        my @ViewableTicketsTmp = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            Limit => 1000,
            StateIDs => \@StateIDs,
            Locks => ['lock'],
            OwnerIDs => [$Self->{UserID}],
            OrderBy => $OrderBy,
            SortBy => $SortByS,
            UserID => 1,
            Permission => 'ro',
        );
        foreach my $TicketID (@ViewableTicketsTmp) {
            my @Index = $Self->{TicketObject}->ArticleIndex(TicketID => $TicketID);
            if (@Index) {
                my %Article = $Self->{TicketObject}->ArticleGet(ArticleID => $Index[$#Index]);
                if ($Article{UntilTime} < 1) {
                    push (@ViewableTickets, $TicketID);
                }
            }
        }
    }
    elsif ($Self->{Subaction} eq 'New') {
        @ViewableTickets = ();
        my @ViewableTicketsTmp = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            Limit => 1000,
#            StateType => 'Open',
            Locks => ['lock'],
            OwnerIDs => [$Self->{UserID}],
            OrderBy => $OrderBy,
            SortBy => $SortByS,
            UserID => 1,
            Permission => 'ro',
        );
        foreach my $TicketID (@ViewableTicketsTmp) {
            my $Message = '';

            # put all tickets to ToDo where last sender type is customer / system or ! UserID
            # show just unseen tickets as new
            if ($Self->{ConfigObject}->Get('Ticket::NewMessageMode') eq 'ArticleSeen') {
                my @Index = $Self->{TicketObject}->ArticleIndex(TicketID => $TicketID);
                if (@Index) {
                    my %Article = $Self->{TicketObject}->ArticleGet(ArticleID => $Index[$#Index]);
                    my %Flag = $Self->{TicketObject}->ArticleFlagGet(
                        ArticleID => $Article{ArticleID},
                        UserID => $Self->{UserID},
                    );
                    if (!$Flag{seen}) {
                        $Message = 'New message!';
                    }
                }
            }
            else {
                my @Index = $Self->{TicketObject}->ArticleIndex(TicketID => $TicketID);
                if (@Index) {
                    my %Article = $Self->{TicketObject}->ArticleGet(ArticleID => $Index[$#Index]);
                    if ($Article{SenderType} eq 'customer' ||
                        $Article{SenderType} eq 'system' ||
                        $Article{CreatedBy} ne $Self->{UserID}) {
                        $Message = 'New message!';
                    }
                }
            }
            if ($Message) {
                push (@ViewableTickets, $TicketID);
            }
        }
    }
    elsif ($Self->{Subaction} eq 'Responsible') {
        @ViewableTickets = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            Limit => 1000,
            StateType => 'Open',
            ResponsibleIDs => [$Self->{UserID}],
            OrderBy => $OrderBy,
            SortBy => $SortByS,
            UserID => 1,
            Permission => 'ro',
        );
    }
    elsif ($Self->{Subaction} eq 'Watched') {
        @ViewableTickets = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            Limit => 1000,
            OrderBy => $OrderBy,
            SortBy => $SortByS,
            WatchUserIDs => [$Self->{UserID}],
            UserID => 1,
            Permission => 'ro',
        );
    }
    else {
        @ViewableTickets = $Self->{TicketObject}->TicketSearch(
            Result => 'ARRAY',
            Limit => 1000,
#            StateType => 'Open',
            Locks => ['lock'],
            OwnerIDs => [$Self->{UserID}],
            OrderBy => $OrderBy,
            SortBy => $SortByS,
            UserID => 1,
            Permission => 'ro',
        );
    }

    # get article data
    my $Counter = 0;
    my $CounterShown = 0;
    my $AllTickets = 0;
    if (@ViewableTickets) {
        $AllTickets = $#ViewableTickets+1;
    }
    foreach my $TicketID (@ViewableTickets) {
        $Counter++;
        if ($Counter >= $Self->{StartHit} && $Counter < ($Self->{PageShown}+$Self->{StartHit})) {
            my %Article = ();
            my @ArticleBody = $Self->{TicketObject}->ArticleGet(TicketID => $TicketID);
            if (!@ArticleBody) {
                next;
            }
            %Article = %{$ArticleBody[$#ArticleBody]};
            # return latest non internal article
            foreach my $Content (reverse @ArticleBody) {
                my %ArticlePart = %{$Content};
                if ($ArticlePart{SenderType} eq 'customer') {
                    %Article = %ArticlePart;
                    last;
                }
            }

            my $Message = '';
            # -------------------------------------------
            # put all tickets to ToDo where last sender type is customer / system or ! UserID
            # -------------------------------------------

            # show just unseen tickets as new
            if ($Self->{ConfigObject}->Get('Ticket::NewMessageMode') eq 'ArticleSeen') {
                my %Article = %{$ArticleBody[$#ArticleBody]};
                my %Flag = $Self->{TicketObject}->ArticleFlagGet(
                    ArticleID => $Article{ArticleID},
                    UserID => $Self->{UserID},
                );
                if (!$Flag{seen}) {
                    $Message = 'New message!';
                 }
            }
            else {
                my %Article = %{$ArticleBody[$#ArticleBody]};
                if ($Article{SenderType} eq 'customer' ||
                    $Article{SenderType} eq 'system' ||
                    $Article{CreatedBy} ne $Self->{UserID}) {
                    $Message = 'New message!';
                }
            }
            $CounterShown++;
            $Self->MaskMailboxTicket(
                %Article,
                Message => $Message,
                Counter => $CounterShown,
            );
        }
    }

    # create & return output
    my %PageNav = $Self->{LayoutObject}->PageNavBar(
        Limit => 10000,
        StartHit => $Self->{StartHit},
        PageShown => $Self->{PageShown},
        AllHits => $AllTickets,
        Action => "Action=AgentTicketMailbox",
        Link => "Subaction=$Self->{Subaction}&SortBy=$SortBy&OrderBy=$OrderBy&",
    );
    $Self->{LayoutObject}->Block(
        Name => 'NavBar',
        Data => {
            %LockedData,
            SortBy => $SortBy,
            OrderBy => $OrderBy,
            ViewType => $Self->{Subaction},
            %PageNav,
        }
    );
    # create & return output
    $Output .= $Self->{LayoutObject}->Output(
        TemplateFile => 'AgentTicketMailbox',
        Data => {
            %Param,
        },
    );
    $Output .= $Self->{LayoutObject}->Footer();
    return $Output;
}

sub MaskMailboxTicket {
    my $Self = shift;
    my %Param = @_;
    $Param{Message} = $Self->{LayoutObject}->{LanguageObject}->Get($Param{Message}).' ';
    # get ack actions
    $Self->{TicketObject}->TicketAcl(
        Data => '-',
        Action => $Self->{Action},
        TicketID => $Param{TicketID},
        ReturnType => 'Action',
        ReturnSubType => '-',
        UserID => $Self->{UserID},
    );
    my %AclAction = $Self->{TicketObject}->TicketAclActionData();
    # check if the pending ticket is Over Time
    if ($Param{UntilTime} < 0 && $Param{State} !~ /^pending auto/i) {
        $Param{Message} .= $Self->{LayoutObject}->{LanguageObject}->Get('Timeover').' '.
          $Self->{LayoutObject}->CustomerAge(Age => $Param{UntilTime}, Space => ' ').'!';
    }
    # create PendingUntil string if UntilTime is < -1
    if ($Param{UntilTime}) {
        if ($Param{UntilTime} < -1) {
            $Param{PendingUntil} = "<font color='$Self->{HighlightColor2}'>";
        }
        $Param{PendingUntil} .= $Self->{LayoutObject}->CustomerAge(
            Age => $Param{UntilTime},
            Space => '<br>',
        );
        if ($Param{UntilTime} < -1) {
            $Param{PendingUntil} .= "</font>";
        }
    }
    # do some strips && quoting
    $Param{Age} = $Self->{LayoutObject}->CustomerAge(Age => $Param{Age}, Space => ' ');
    $Self->{LayoutObject}->Block(
        Name => 'Ticket',
        Data => {
            %Param,
            %AclAction,
        },
    );
    # ticket bulk block
    if ($Self->{ConfigObject}->Get('Ticket::Frontend::BulkFeature')) {
        $Self->{LayoutObject}->Block(
            Name => 'Bulk',
            Data => { %Param },
        );
    }
    # ticket title
    if ($Self->{ConfigObject}->Get('Ticket::Frontend::Title')) {
        $Self->{LayoutObject}->Block(
            Name => 'Title',
            Data => { %Param },
        );
    }
    # run ticket pre menu modules
    if (ref($Self->{ConfigObject}->Get('Ticket::Frontend::PreMenuModule')) eq 'HASH') {
        my %Menus = %{$Self->{ConfigObject}->Get('Ticket::Frontend::PreMenuModule')};
        my $Counter = 0;
        foreach my $Menu (sort keys %Menus) {
            # load module
            if ($Self->{MainObject}->Require($Menus{$Menu}->{Module})) {
                my $Object = $Menus{$Menu}->{Module}->new(
                    %{$Self},
                    TicketID => $Self->{TicketID},
                );
                # run module
                $Counter = $Object->Run(
                    %Param,
                    Ticket => \%Param,
                    Counter => $Counter,
                    ACL => \%AclAction,
                    Config => $Menus{$Menu},
                );
            }
            else {
                return $Self->{LayoutObject}->FatalError();
            }
        }
    }
}
1;
