#!/usr/bin/perl -w

#       abzapfit.pl
#
#       Copyright 2011 Philipp Böhm <philipp-boehm@live.de>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
#
#       Script, welches die Dateien aus dem StudIP lokal mirrort um einen
#       einfachen Zugriff auf diese Dateien zu ermöglichen
#
#       TODO Script verallgemeinern (Uni-Rostock-URLs entfernen)
#

use strict;
use Getopt::Long;
use File::Spec::Functions qw{ catfile };
use File::Copy;
use WWW::Mechanize;
use HTML::TreeBuilder;
use Encode qw/:all/;
use URI::Escape;
use Data::Dumper;

my $VERSION = "0.0.3";

################################################################################
############### Parameter erfassen #############################################
################################################################################
my %PARAMS = ( "downloaddir" => catfile( $ENV{"HOME"}, "Downloads" ) );
my @EXCLUDES;

GetOptions(
    \%PARAMS,
    "help" => \&help,
    "verbose",
    "version" => sub { print $VERSION, "\n"; exit; },
    "user=s",
    "password=s",
    "downloaddir=s",
    "queuefornewfiles=s",
    "exclude=s" => \@EXCLUDES,
    "postdownload=s",
) or die "Fehler bei der Parameterübergabe";

die "Download-Verzeichnis existiert nicht" unless -d $PARAMS{"downloaddir"};
die "Downloadverzeichnis nicht schreibbar" unless -w $PARAMS{"downloaddir"};

chdir( $PARAMS{"downloaddir"} );

die "Sie müssen Benutzername und Passwort angeben"
  unless defined $PARAMS{"user"} && defined $PARAMS{"password"};

die "Wenn Sie ein Queue-Verzeichnis angeben muss dies auch existieren"
  if ( defined $PARAMS{"queuefornewfiles"} && !-d $PARAMS{"queuefornewfiles"} );

die "Post-Download-Script muss existieren und ausführbar sein"
  if ( defined $PARAMS{"postdownload"} && !-x $PARAMS{"postdownload"} );

################################################################################
############## Login durchführen ###############################################
################################################################################
my $BROWSER = WWW::Mechanize->new(
    stack_depth => -1,
    timeout     => 180,
    autocheck   => 1,
    agent       => "abzapfit/libwww-perl",
    cookie_jar  => {},
);
$BROWSER->quiet(1);

$BROWSER->get('https://studip.uni-rostock.de/index.php?again=yes');

$BROWSER->form_number(1);

$BROWSER->field( "loginname", $PARAMS{"user"} );
$BROWSER->field( "password",  $PARAMS{"password"} );

$BROWSER->click();

die "Login nicht erfolgreich"
  if defined $BROWSER->form_with_fields( "loginname", "password" );

################################################################################
#################### Veranstaltungen mit Dateien suchen ########################
################################################################################
$BROWSER->get('https://studip.uni-rostock.de/meine_seminare.php');

EVENTS:
for
  my $l ( $BROWSER->find_all_links( url_regex => qr/redirect_to=folder.php/ ) )
{
    my $url = $l->url();
    $url =~ s/cmd=.*/cmd=all/;

    $BROWSER->get($url);

    #####
    # Namen der Veranstaltung aus Seitentitel extrahieren und bereinigen
    # und entsprechendes Verzeichnis anlegen
    my ($event_name) = $BROWSER->title() =~ /: (.+) - Dateien.*$/;
    next unless defined $event_name;
    from_to( $event_name, "cp1252", "utf-8" );

    #######
    # Excludes auf Veranstaltung anwenden
    for my $exclude (@EXCLUDES) {
        if ( $event_name =~ /${exclude}/ ) {
            next EVENTS;
        }
    }

    # Veranstaltung bereinigen und jeweiligen Ordner erstellen
    $event_name =~ s/\s/_/g;
    print "=== Veranstaltung: ", $event_name, "\n";

    mkdir($event_name) unless -d $event_name;
    chdir($event_name);

    #####
    # Infos über Dateien laden
    # dbmopen( my %FILE_INFOS, ".fileinfo", 0666 );

    #####
   # Veröffentlichungsdaten laden
   # my %DATES = ();
   # my $root  = HTML::TreeBuilder->new_from_content( $BROWSER->content() );
   # for my $fileinfo ( $root->look_down( '_tag', 'td', 'class', 'printhead' ) )
   # {

#     my $id = $fileinfo->look_down( '_tag', 'input');
#
#     if ( my ($date) = $fileinfo->as_text() =~ /(\d{2}.\d{2}.\d{4}.-.\d{2}:\d{2})/ )
#     {
#         print $date, "\n";
#     }

    #     # if ( my $file_id = $filediv->look_down( 'id', qr/^getmd5_fi.*/ ) ) {
    #     #     my $id = $file_id->as_text();

    #     #     if ( my ($date) =
    #     #         $filediv->as_text() =~ /(\d{2}.\d{2}.\d{4}.-.\d{2}:\d{2})/ )
    #     #     {
    #     #         $DATES{$id} = $date;
    #     #     }
    #     # }
    # }

    # next;

    #####
    # Dateien durchlaufen
    for my $filelink_uri (
        $BROWSER->find_all_links(
            url_regex => qr/sendfile.php.*file_id=.*file_name=/
        )
      )
    {
        my $link = $filelink_uri->URI()->abs();

        #####
        # Dateinamen und ID aus URL extrahieren und wenn nicht vorhanden
        # herunterladen
        if ( my ( $file_id, $file_name_escaped ) =
            $link =~ /file_id=(.*)&.*file_name=(.*)/ )
        {
            my $file_name = uri_unescape($file_name_escaped);

            if ( -f $file_name ) {

                next;

                # if (   defined $FILE_INFOS{$file_name}
                #     && defined $DATES{$file_id}
                #     && ( $FILE_INFOS{$file_name} eq $DATES{$file_id} ) )
                # {
                #     next;
                # }

                # printf "%s wurde geändert\n", $file_name;
            }

            printf "%s wird heruntergeladen\n", $file_name;

            # $FILE_INFOS{$file_name} = $DATES{$file_id};

            $BROWSER->get($link);
            $BROWSER->save_content($file_name);

            ####
            # PostDownload-Script ausführen falls angegeben
            if ( defined $PARAMS{"postdownload"} && -x $PARAMS{"postdownload"} )
            {
                system( sprintf "%s %s %s",
                    $PARAMS{"postdownload"}, $file_name, $event_name );
            }

            ####
            # neue Dateien in Queue-Verzeichnis kopieren
            if ( defined $PARAMS{"queuefornewfiles"} ) {
                copy( $file_name,
                    catfile( $PARAMS{"queuefornewfiles"}, $file_name ) )
                  or die "Konnte $file_name nicht kopieren";
            }
        }
    }

    # dbmclose(%FILE_INFOS);
    chdir("..");
}

################################################################################
############## Funktionsdefinitionen ###########################################
################################################################################

sub help {
    print << "EOF";

Copyright 2011 Philipp Böhm

Script, welches die Dateien aus dem StudIP lokal mirrort um einen
einfachen Zugriff auf diese Dateien zu ermöglichen
    
Usage: $0 [Optionen]

   --help                 : Diesen Hilfetext ausgeben
   --verbose              : erweiterte Ausgaben
   --version              : Versionshinweis
   --user=STRING          : Nutzername für das StudIP
   --password=STRING      : Passwort für den Account im StudIP
   --downloaddir=DIR      : Verzeichnis in welches die Dateien
                            heruntergeladen werden
   --queuefornewfiles=DIR : Verzeichnis, in welches alle neue Dateien kopiert
                            werden, sodass sie von da aus weiterverarbeitet
                            werden können
   --exclude=REGEX        : Ermöglicht es, Veranstaltungen vom Mirrorn
                            auszuschließen. Dafür muss ein Regulärer Ausdruck
                            als String übergeben werden, der auf die jeweilige
                            Veranstaltung passt.
                            --> Option kann mehrfach übergeben werden
   --postdownload=FILE    : Möglichkeit der Angabe eines Scriptes, welches für
                            jede neue heruntergeladene Datei ausgeführt wird und 
                            dabei den Pfad zur aktuellen Datei als ersten Parameter
                            und den Namen der Veranstaltung als zweiten Parameter
                            übergibt. Somit besteht die Möglichkeit der Einflussname
                            auf neue Dateien. So wäre ein Anwendungsfall, das Entfernen
                            von Passwörtern von PDF-Dateien ...
EOF

    exit();
}
