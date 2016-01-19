#RemoveMozillaDuplicates.pl
# Goes through Firefox 3.x bookmarks and removes duplicate entries
#Modification History
# 27-JAN-2010: GGARIEPY: Created, after discovering that Firefox doesn't have this...

=head1 Copyright Notice

--------------------------------
Copyright (C)2010 Geoff Gariepy
--------------------------------

=cut

use strict;
use feature ':5.10';

use DBI;
system('cls');

# Launch the DBI SQLite driver (which is itself a Perl SQLite engine implementation)
say "Connecting to Firefox bookmarks database (the Library)";
my $dbh = DBI->connect("dbi:SQLite:dbname=$ENV{'USERPROFILE'}/application data/Mozilla/Firefox/Profiles/cs6cmmun.default/places.sqlite","","") 
          or die(DBI->errstr);

# Prepare our SQL query
my $folders = $dbh->prepare(<<PARENTS) or die(DBI->errstr);
select
	moz_bookmarks.id as [ID],
	moz_bookmarks.title as [Bookmarks_Title],
     moz_bookmarks.parent as [Bookmark_Parent]
from
	moz_bookmarks
where
	moz_bookmarks.type = 2 
order by
	id asc,
	moz_bookmarks.title asc
PARENTS

$folders->execute() or die(DBI->errstr);
my $parentfolders = {};
while (my @data = $folders->fetchrow_array()) {
     $parentfolders->{$data[0]}{title} = $data[1];
     $parentfolders->{$data[0]}{parent} = $data[2];
}

my $bookmarks = $dbh->prepare(<<BOOKMARKS) or die(DBI->errstr);
select 
	moz_bookmarks.id as [ID],
	moz_bookmarks.title as [Bookmarks_Title],
     moz_bookmarks.parent as [Bookmark_Parent],
	moz_places.url as [URL],
     moz_bookmarks.fk as [Key]
from
	moz_bookmarks join moz_places on moz_bookmarks.fk = moz_places.id
where
	moz_places.hidden = 0 and
	moz_bookmarks.type = 1 and
     moz_bookmarks.title != 'Tags'
BOOKMARKS

my $del = $dbh->prepare(<<DELSQL) or die(DBI->errstr);
delete from moz_bookmarks where moz_bookmarks.id = ?
DELSQL

# Execute the query and get the results into the $urldata hash keyed by URL
say "Executing bookmarks query";
my $bookmarkcounter = 0;
my $urldata = {};
$bookmarks->execute() or die(DBI->errstr);
while (my @data = $bookmarks->fetchrow_array()) {
     my ($id, $title, $parent, $url, $fkey) = @data;
     my $parentstring = '';
     my $parentid = $parent;
     my @path;
     while ($parentid != 0) {
          push(@path, $parentfolders->{$parentid}{title});
          $parentid = $parentfolders->{$parentid}{parent};
     }
     for (my $i = scalar(@path) - 1; $i >= 0; $i--) {
          $parentstring .= $path[$i] . '\\';
     }
     $parentstring =~ s/\\\\//;
     chop($parentstring);
     next unless ($url =~ /^http:/);
     $urldata->{$id}{title} = $title if ($title);
     $urldata->{$id}{parent} = $parentstring;
     $urldata->{$id}{url} = $url ? $url : 'none';
     $urldata->{$id}{fkey} =  $fkey ? $fkey : 'none';
     $bookmarkcounter++;
}

say "$bookmarkcounter Bookmarks loaded, searching for duplicates";

my $urlhash = {};
my $duplicatecounter = 0;
foreach my $id (keys(%$urldata)) {
     if (exists $urlhash->{$urldata->{$id}{url}}) {
          # Duplicate found
          say ++$duplicatecounter.": I've found $urldata->{$id}{url} more than once.";
          say "\t\tID: [$id] ".$urldata->{$id}{parent} . '\\' . $urldata->{$id}{title};
          say "\t\tID: [$urlhash->{$urldata->{$id}{url}}] ".$urldata->{$urlhash->{$urldata->{$id}{url}}}{parent} . '\\' . $urldata->{$urlhash->{$urldata->{$id}{url}}}{title};
          my $default = ($id < $urlhash->{$urldata->{$id}{url}}) ? $id : $urlhash->{$urldata->{$id}{url}};
          print "Enter an ID number if you wish to delete one of these [$default] >";
          my $delid = <STDIN>;
          if ($delid !~ /\d/) {$delid = $default;}
          chomp $delid;
          if (($delid != $id) and ($delid !=$urlhash->{$urldata->{$id}{url}})) {
               say "Skipping it then.";
               next;
          }
          else {
               print "Deleting [$delid] (this cannot be undone) -- correct? >";
               my $yorn = <STDIN>;
               if ($yorn =~ /y/i) {
                    $del->execute($delid);
                    delete $urlhash->{$delid};
                    say "Done.";
               }
          }
     }
     else {
          $urlhash->{$urldata->{$id}{url}} = $id;
     }
}



$dbh->disconnect;
undef($bookmarks);
undef($dbh);