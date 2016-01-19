#!/usr/bin/perl

=head1 GetDealerInventory.pl

This program grabs used Ram pickup truck inventory from car dealership
websites.

It scrapes the details concerning price, color, VIN, etc., and then
decodes the VIN.

This program will run unmodified on Windows with Active State Perl 5.014
and the HTML::TokeParser::Simple module installed.

=head2 Modification History

=over4

=item * 31-OCT-2013: GGARIEPY: Proof of concept

=back

=cut

use 5.014;
use HTML::TokeParser::Simple;
use DBI;
use Data::Dumper;
use Try::Tiny;

use constant {
	FALSE => 0,
	TRUE=> 1,
};


system('cls');

my $current_date_time = GetCurrentDateTime();
my $vehicle_database;
my $do_not_purge;		# Set to TRUE if a failure occurs during web retrieval

say 'Retrieving data from dealer websites';
($vehicle_database, $do_not_purge)  = Retrieve_Web_Data();

if (ref $vehicle_database ne 'HASH') {
	die "Did not successfully retrieve data!\n";
}

say "\n\n************************************************\nRetrieved data from web, updating local database\n************************************************";

my $dealer_hash = {};
open my $ofh, '>', 'RAM 1500s for sale.txt';
foreach my $vin (keys $vehicle_database) {
	my $details = $vehicle_database->{$vin};
	my $dealer = $details->{'Dealer'};
	if (defined $dealer_hash->{$dealer}) {
		my $aref = $dealer_hash->{$dealer};
		push @$aref, $vin;
	}
	else {
		my $aref = [];
		push @$aref, $vin;
		$dealer_hash->{$dealer} = $aref;
	}
}

my $dbh = Connect_To_Database();
my $sth = $dbh->prepare(<<'FINDVIN');
select
     [Dealer_URL],
     [Carfax_URL],
     [VIN_Model Year],
     [Asking_Price],
     [Trim_Level],
     [Advertised_Mileage],
     [Display_Vehicle],
     [Dealer_ID],
     [Date_First_Seen],
     [Date_Last_Seen],
     [Days_On_Market],
     [Body_Style],
	 [Is_4WD],
     [Is_Certified_Pre_Owned],
     [Change_Date_Description],
     [Photo],
     [Interior_Color],
     [Exterior_Color],
     [Engine]
from
     Vehicle
where
     [VIN] = ?
FINDVIN


foreach my $dealer (sort keys $dealer_hash) {
	my $aref = $dealer_hash->{$dealer};
	say "Recording " .scalar(@$aref) . " vehicles found at $dealer in database";
	my $vehicle_data_from_db;

	foreach my $vin (@$aref) {
		my $details = $vehicle_database->{$vin};
          if ($details->{'url'} =~ /certified/i) {
               $details->{'certified'} = 'Yes';
          }
          else {
               $details->{'certified'} = 'No';
          }

          # Check to see if we have seen this VIN before
          $sth->execute($vin);
          if ($vehicle_data_from_db = $sth->fetchrow_hashref) {
               my $sql_update = Compare_Data($vin, $vehicle_data_from_db, $vehicle_database->{$vin});

               if ($sql_update eq 'NOCHANGE') {
					my $update_handle = $dbh->prepare("update vehicle set Date_Last_Seen = Datetime('now'), Days_On_Market = julianday('now') - julianday(Date_First_Seen) where VIN = '$vin'");
                    $update_handle->execute();
               }
               else {
                    say "\tChanges found, updating database";
                    my $update_handle = $dbh->prepare($sql_update);
                    $update_handle->execute();
               }
          }
          else {
               say "VIN [$vin] is new...adding vehicle to database";
               if ($details->{'price'} !~ /^\$\d+,*\d+$/) {
                    $details->{'price'} = '$NOPRICE';
               }

			   Add_New_Vehicle($details, $vin);
          }

		print $ofh <<"SIMPLEREPORT";

Dealer: $details->{'Dealer'}
VIN: $vin
Stock Number: $details->{'Stock Number'}
Seen at: $details->{'url'}
Price: $details->{'price'}

$details->{'VIN_Model Year'} $details->{'VIN_Make'} $details->{'VIN_Model Line and Vehicle Family'} $details->{'VIN_Series/Price Class'}
$details->{'Bodystyle'}
Color:	$details->{'Ext. Color'}
Interior: $details->{'Int. Color'}
Mileage: $details->{'Mileage'}
Engine: $details->{'VIN_Engine'}
Carfax? $details->{'carfax'}
*********************************************
SIMPLEREPORT
	}
}
close $ofh;

# Clean up old vehicles in database unless we recorded trouble in
# retrieving data from the web
if ($do_not_purge == FALSE) {
	say "Cleaning up vehicles in the database we haven't seen during this run.";
	Check_For_Sold($current_date_time);
	exit(TRUE);
}
else {
	say "Unsafe to run old vehicle clean-up, recorded trouble retrieving data from web.";
	exit(FALSE);
}


=head2 Connect_To_Database()

Locates the database path on the current machine and returns a
connected DBI database handle.  The database is being kept on
a Dropbox account and the link to it on the local file system is
different for Windows 8 vs. Windows XP.

=cut

sub Connect_To_Database {
	my $dbfile;
	if (-e 'C:\\Users\\geoff\\Dropbox\\VIN Project\\database\\VehicleRecords.db') {
		$dbfile = 'C:\\Users\\geoff\\Dropbox\\VIN Project\\database\\VehicleRecords.db';
	}
	elsif (-e 'C:\\Users\\GEGA\\Dropbox\\VIN Project\\database\\VehicleRecords.db') {
		$dbfile = 'C:\\Users\\GEGA\\Dropbox\\VIN Project\\database\\VehicleRecords.db';
	}
	else {
		die "Could not locate database!";
	}

	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","");
	return $dbh;
}


=head2 Add_New_Vehicle

Adds a newly discovered vehicle to the local database.

=cut

sub Add_New_Vehicle {
	my $details = shift;
	my $vin = shift;
	my $dbh = Connect_To_Database();
	my $entered = ": Entered into database\n";

	my $sql = <<"ADDSQL";
		insert into vehicle values (
			 '$vin',
			 '$details->{'url'}',
			 '$details->{'carfax'}',
			 '$details->{'VIN_Model Year'}',
			 '$details->{'price'}',
			 null,                    --Trim_Level_Place_Holder
			 '$details->{'Mileage'}',
			 1,               --[Display_Vehicle],
			 '$details->{'Dealership_ID'}',
			 DateTime('now'),
			 DateTime('now'),
			 1,               --[Days_On_Market],
			 '$details->{'Bodystyle'}',
			'$details->{'Is_4WD'}',
			 '$details->{'certified'}',
			 DateTime('now') || '$entered',
			 null,               --[Photo],
			 '$details->{'Int. Color'}',
			 '$details->{'Ext. Color'}',
			 '$details->{'VIN_Engine'}')
ADDSQL
	my $add_handle = $dbh->prepare($sql);
	$add_handle->execute();
	return;
}

=head2 Check_For_Sold()

Compares previous list of dealer vehicles to current list from website,
and marks any that are no longer showing on the website in the database.

Note: vehicles are not deleted by this routine, that will have to be
done by an external program.

=cut

sub Check_For_Sold {
	my $current_time = shift;
	my $dbh = Connect_To_Database();

	my $update_handle = $dbh->prepare("update VEHICLE set Display_Vehicle = 0, Days_on_Market = julianday('now') - julianday(Date_First_Seen), Change_Date_Description = ? where VIN = ?");

	my $search_handle = $dbh->prepare("select VIN, Date_Last_Seen, Days_On_Market, Change_Date_Description from VEHICLE where (Date_Last_Seen < date('$current_time') or Date_Last_Seen is null) and Display_Vehicle = 1");
	$search_handle->execute();
	while (my $old_vehicle = $search_handle->fetchrow_hashref) {
		my $vin = $old_vehicle->{'VIN'};
		my $date_last_seen = $old_vehicle->{'Date_Last_Seen'};
		my $change_description = $old_vehicle->{'Change_Date_Description'} . "\n$current_time : Disappeared from dealer website";
		say "VIN [$vin] was last seen at [$date_last_seen], before current time of [$current_time], setting Display_Vehicle to 0";
		say "Change description field: [$change_description]";
		$update_handle->execute($change_description, $vin);
	}
	return;
}


=head2 GetCurrentDateTime()

Runs at beginning of execution, returns the current date and time
as a SQL date time string.

=cut

sub GetCurrentDateTime {

	my $dbh = Connect_To_Database();
	my $now;
	my $sth = $dbh->prepare("select DateTime('now') as [Current]");
	$sth->execute();
	if (my $current_time = $sth->fetchrow_hashref) {
		$now = $current_time->{'Current'};
	}
	return($now);
}

=head2 Compare_Data()

Compares data in the database to what the dealership website says currently

=cut

sub Compare_Data {
	my $vin = shift;
	my $db_data = shift;
	my $web_data = shift;
	my $change_found = FALSE;

	if ($web_data->{'price'} !~ /^\$\d+,*\d+$/) {
	  $web_data->{'price'} = '$NOPRICE';
	}
	my $change_text = "VIN: $vin\n";
	my $sql_statement = "update vehicle set\nDate_Last_Seen = DateTime('now'),";
	my $change_description = "$db_data->{'Change_Date_Description'}' || ' *** ' || DateTime('now') || ': ";

	if ($db_data->{'Dealer_ID'} ne $web_data->{'Dealership_ID'} and $web_data->{'Dealership_ID'} ne '') {
	  $change_text .= "\tDealership_ID is different\n";
	  $change_found = TRUE;
	  $sql_statement .= "\nDealer_ID = '$web_data->{'Dealership_ID'}',";
	  $change_description .= "Dealership_ID changed from [".$db_data->{'Dealer_ID'}.'] to [' . $web_data->{'Dealership_ID'}."]\n";
	}
	elsif ($db_data->{'Dealer_ID'} ne $web_data->{'Dealership_ID'} and $web_data->{'Dealership_ID'} eq '') {
		say "Error retrieving dealership ID for VIN [$vin] from web.  Not recording a change.";
	}

	if ($db_data->{'Is_4WD'} ne $web_data->{'Is_4WD'} and $web_data->{'Is_4WD'} ne '') {
	  $change_text .= "\tDrivetrain is different\n";
	  $change_found = TRUE;
	  $sql_statement .= "\nIs_4WD = '$web_data->{'Is_4WD'}',";
	  $change_description .= "Drivetrain changed from [".$db_data->{'Is_4WD'}.'] to [' . $web_data->{'Is_4WD'}."]\n";
	}
	elsif ($db_data->{'Is_4WD'} ne $web_data->{'Is_4WD'} and $web_data->{'Is_4WD'} eq '') {
		say "Error retrieving drivetrain for VIN [$vin] from web.  Not recording a change.";
	}
if ($db_data->{'Dealer_URL'} ne $web_data->{'url'} and $web_data->{'url'} ne '') {
	  $change_text .= "\tURL is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nDealer_URL = '$web_data->{'url'}',";
	  $change_description .= "URL changed from [".$db_data->{'Dealer_URL'}.'] to [' . $web_data->{'url'}."]\n";
	}
	elsif ($db_data->{'Dealer_URL'} ne $web_data->{'url'} and $web_data->{'url'} eq '') {
		say "Error retrieving vehicle URI for VIN [$vin] from web.  Not recording a change.";
	}

	if ($db_data->{'Carfax_URL'} ne $web_data->{'carfax'} and $web_data->{'carfax'} ne '') {
	  $change_text .= "\tCARFAX URL is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nCarfax_URL = '$web_data->{'carfax'}',";
	  $change_description .= "CARFAX URL changed from [".$db_data->{'Carfax_URL'}.'] to [' . $web_data->{'carfax'}."]\n";
	}
	elsif ($db_data->{'Dealer_URL'} ne $web_data->{'url'} and $web_data->{'url'} eq '') {
		say "Error retrieving vehicle URI for VIN [$vin] from web.  Not recording a change.";
	}

	if ($db_data->{'Asking_Price'} ne $web_data->{'price'} and $web_data->{'price'} ne '' and $web_data->{'price'} =~ /\d+/) {
	  $change_text .= "\t***Price is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nAsking_Price = '$web_data->{'price'}',";
	  $change_description .= "Price changed from [".$db_data->{'Asking_Price'}.'] to [' . $web_data->{'price'}."]\n";
	}
	elsif ($db_data->{'Asking_Price'} ne $web_data->{'price'} and $web_data->{'price'} eq '') {
		say "Error retrieving asking price for VIN [$vin] from web.  Not recording a change.";
	}


	if ($db_data->{'Advertised_Mileage'} ne $web_data->{'Mileage'} and $web_data->{'Mileage'} ne '' and $web_data->{'Mileage'} =~ /\d+/) {
	  $change_text .= "\tMileage is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nAdvertised_Mileage = '$web_data->{'Mileage'}',";
	  $change_description .= "Mileage changed from [".$db_data->{'Advertised_Mileage'}.'] to [' . $web_data->{'Mileage'}."]\n";
	}
	elsif ($db_data->{'Advertised_Mileage'} ne $web_data->{'Mileage'} and $web_data->{'Mileage'} eq '') {
		say "Error retrieving mileage for VIN [$vin] from web.  Not recording a change.";
	}


	if ($db_data->{'Is_Certified_Pre_Owned'} ne $web_data->{'certified'} and $web_data->{'certified'} ne '') {
	  $change_text .= "\tCertified/Pre-Owned is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nIs_Certified_Pre_Owned = '$web_data->{'certified'}',";
	  $change_description .= "Certified/Pre-Owned changed from [".$db_data->{'Is_Certified_Pre_Owned'}.'] to [' . $web_data->{'certified'}."]\n";
	}
	elsif ($db_data->{'Is_Certified_Pre_Owned'} ne $web_data->{'certified'} and $web_data->{'certified'} eq '') {
		say "Error retrieving CPO for VIN [$vin] from web.  Not recording a change.";
	}


	if ($db_data->{'Interior_Color'} ne $web_data->{'Int. Color'} and $web_data->{'Int. Color'} ne '') {
	  $change_text .= "\tInterior color is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nInterior_Color = '$web_data->{'Int. Color'}',";
	  $change_description .= "Interior color changed from [".$db_data->{'Interior_Color'}.'] to [' . $web_data->{'Int. Color'}."]\n";
	}
	elsif ($db_data->{'Interior_Color'} ne $web_data->{'Int. Color'} and $web_data->{'Int. Color'} eq '') {
		say "Error retrieving interior color for VIN [$vin] from web.  Not recording a change.";
	}


	if ($db_data->{'Exterior_Color'} ne $web_data->{'Ext. Color'} and $web_data->{'Ext. Color'} ne '') {
	  $change_text .= "\tInterior color is different";
	  $change_found = TRUE;
	  $sql_statement .= "\nExterior_Color = '$web_data->{'Ext. Color'}',";
	  $change_description .= "Exterior color changed from [".$db_data->{'Exterior_Color'}.'] to [' . $web_data->{'Ext. Color'}."]\n";
	}
	elsif ($db_data->{'Exterior_Color'} ne $web_data->{'Ext. Color'} and $web_data->{'Ext. Color'} eq '') {
		say "Error retrieving exterior color for VIN [$vin] from web.  Not recording a change.";
	}


	$change_found and $sql_statement .= "\nChange_Date_Description = '$change_description'\nwhere VIN='$vin'";
	$change_found and say $change_text;
	$change_found and return($sql_statement);

	return 'NOCHANGE';
}


=head2 Retrieve_Web_Data()

Retrieves vehicle data from dealership websites.

Current code is written for websites produced for Chrysler dealers
by Dealer.com.  In the future, this routine will become a Moose
class, and it will be joined by other Moose classes with the same
API but designed to process websites produced by different vendors.

=cut

sub Retrieve_Web_Data {

     my $dbh = Connect_To_Database();
     my $sth = $dbh->prepare(<<'SELECTDEALERS');
select
      Dealership_ID,
      dealer_name,
      dealer_website,
	  URI_Location_Modifier
from
    dealership
SELECTDEALERS
	my $dealerurls;
     $sth->execute();
     while (my $row = $sth->fetchrow_hashref) {
          my $dealer_name = $row->{'Dealer_Name'};
          my $dealer_web  = $row->{'Dealer_Website'};
          my $dealer_id   = $row->{'Dealership_ID'};
          $dealerurls->{$dealer_name}{'Dealer_Website'} = $dealer_web;
          $dealerurls->{$dealer_name}{'Dealership_ID'} = $dealer_id;
		  if (defined $row->{'URI_Location_Modifier'} and $row->{'URI_Location_Modifier'} ne '') {
			  $dealerurls->{$dealer_name}{'URI_Location_Modifier'} = $row->{'URI_Location_Modifier'};
		  }
     }

	my $baseurl;
	my $vehicle_database = {};
	my $do_not_purge = FALSE;
	my @search_uris = ();
	push @search_uris, '/used-inventory/index.htm?invtype=used&reset=InventoryListing&SBmake=Ram&SBmodel=1500&SBbodystyle=clear&SBprice=clear';
	push @search_uris, '/used-inventory/index.htm?invtype=used&reset=InventoryListing&SBmake=Dodge&SBmodel=Ram+1500&SBbodystyle=clear&SBprice=clear';
	my $failcount;

	DEALERWEBSITE:
	foreach my $dealer (sort keys %$dealerurls) {
		$baseurl = $dealerurls->{$dealer}{'Dealer_Website'};
		my $dealer_id = $dealerurls->{$dealer}{'Dealership_ID'};
		say "\n\n\********\nScraping website for [$dealer]";

		foreach my $search_uri (@search_uris) {
			if ($dealerurls->{$dealer}{'URI_Location_Modifier'}) {
				say "Adding in URI_Location_Modifier for [$dealer]";
				$search_uri .= $dealerurls->{$dealer}{'URI_Location_Modifier'};
			}
			my $parser;
			try {
				$parser = HTML::TokeParser::Simple->new(url => $baseurl.$search_uri);
			}
			catch {
				if ($_ =~ /Could not fetch content/) {
					say "Unable to retrieve data from [$dealer] website, skipping";
					$do_not_purge = TRUE;
					next DEALERWEBSITE;
				}
				else {
					say "Unusual error from HTML::TokeParser::Simple, skipping this dealership website\n$_";
					next DEALERWEBSITE;
				}
			};
			my $pagecount = 1;

			my $seen_pages = {};
			$seen_pages->{0} = 1;
			my $seen_hrefs = {};
			my $seen_forms;

			# Current dealer page structure as of 31-OCT-2013:
			# Page has two forms, a list of vehicles, then a list of pages to jump to, plus a bunch of javascript crap.
			# Must see the two forms end first, because the list of pages to jump to is repeated twice.
			# Otherwise, will skip over all the vehicles!

			# Vehicle details are located on separate pages linked via HREFs that encode the
			# basic vehicle description.Those HREFs are repeated multiple times per vehicle, hence
			# the filtering done via the $seen_hrefs hash.

			while ( my $token = $parser->get_token ) {
				# Count the number of times we see </form>
				if ($token->is_end_tag('form')) {
					$seen_forms++;
				}
				# If we see an <a> tag, look at the raw data.
				# If it seems to match the vehicle type we're looking for and isn't a repeat of an earlier tag,
				# grab the href attribute, then shunt off to the routine to get the
				# detailed info and read up on it.
				if ($token->is_start_tag('a') and $token->as_is =~ /(2009|2010|2011|2012|2013|2014|2015).+Ram/i and $seen_hrefs->{$token->as_is} == undef and $token->get_attr('href') ne '#') {
					my $href = $token->get_attr('href');
					$seen_hrefs->{$token->as_is} = 1;
					my $details_hash = ParseVehicleHTML($baseurl.$href);
					if ($details_hash->{'retrieved_url'} == FALSE) {
						say "Didn't retrieve data for this vehicle.";
						$do_not_purge = TRUE;		# Prevent accidentally removing this vehicle from the database in a later step.
					}
					else {
						$details_hash->{'Dealer'} = $dealer;
						$details_hash->{'Dealership_ID'} = $dealer_id;
						my $vin = $details_hash->{'vin'};
                              if ($vin gt '') {
                                   say "Found VIN: $vin";
     						$vehicle_database->{$vin} = $details_hash;
                              }
                              else {
                                   say "NO VIN FOUND!  SKIPPING!";
                              }
					}

				}
				# Otherwise, if we've seen two forms,
				# and the <a> tag's raw data indicates a ?start=### URL modifier
				# check to see if it's a page we've visited.If not, then append
				# the ?start=### to the base URL and hop to the next page of
				# wholesale inventory.

				elsif ($seen_forms == 2 and $token->is_start_tag('a') and $token->as_is =~ /\?start=(\d+)/i and $seen_pages->{$1} == undef) {
					my $nextpage = $token->get_attr('href');
					say "Saw link to next page: $nextpage";
					$seen_forms = 0;
					$seen_pages->{$1} = 1;
                         try {
					     $parser = HTML::TokeParser::Simple->new(url => $baseurl.'/wholesale-inventory/listview_ajax.htm'.$nextpage);
                         }
                         catch {
                              say "Oh, shit, the last web retrieve failed from $baseurl";
                         };
				}
			}
		}
	}

	return($vehicle_database, $do_not_purge);
}


=head2 ParseVehicleHTML()

Retrieves the HTML from the dealership website which contains
details on a vehicle matching our criteria.

Current code is written for websites produced for Chrysler dealers
by Dealer.com.  In the future, this routine will become a Moose
class, and it will be joined by other Moose classes with the same
API but designed to process websites produced by different vendors.

=cut

sub ParseVehicleHTML {
	my $url = shift;
     say "Enter ParseVehicleHTML";
	my $details_hash = {};
	$details_hash->{'url'} = $url;

	my $vehiclepageparser;

	try {
		$vehiclepageparser= HTML::TokeParser::Simple->new(url => $url);
          say "Retrieving $url";
	}
	catch {
		say "Attempt to retrieve data on this vehicle failed!  Skipping";
		$details_hash->{'retrieved_url'} = FALSE;
		return;
	};

	$details_hash->{'retrieved_url'} = TRUE;

	# Loop through all the data on a vehicle detail page
	my $value_type;
	my $value;
     my $token;

     try {
	    $token = $vehiclepageparser->get_token;
     }
     catch {
          say "Error attempting to retrieve information on vehicle at $url, skipping";
          $details_hash->{'retrieved_url'} = FALSE;
		return;
     };

     if ($token == '') {
          say "Didn't retrieve info on vehicle at $url as expected, skipping";
          $details_hash->{'retrieved_url'} = FALSE;
		return;
     }

	while ((! $token->is_start_tag('strong')) and $token->get_attr('class') !~ /price/i) {
		$token = $vehiclepageparser->get_token;
	}

	FINDPRICE:
	while ($token = $vehiclepageparser->get_token) {
		if ($token->is_start_tag('strong') and $token->get_attr('class') eq 'h1 price') {
               #say "Found the price heading:" . $token->as_is;
			last FINDPRICE;
		}
	}

	PRICELOOP:
	# Find the price
	while ($token = $vehiclepageparser->get_token) {
		if ($token->as_is =~ /\$/) {
			$value = $token->as_is;
              # say "Got $value";
			chomp($value);
			$details_hash->{'price'} = $value;
			last PRICELOOP;
		}
		elsif ($token->is_end_tag('dl')) {
              # say "Reached the end";
			last PRICELOOP;
		}
		if ($token == undef) {
			say "Error!  Ran out of data!";
			return;
		}
	}

	if (! defined $details_hash->{'price'}) {
		$details_hash->{'price'} = '$NOPRICE';
	}

	DETAILSLOOP:
	while ($token = $vehiclepageparser->get_token) {
          if ($token->is_start_tag('li') and $token->get_attr('class') =~ /\b(driveLine|transmission|bodystyle|odometer|stocknumber|model|vin|exteriorcolor|int. color)\b/i) {
			$value_type = lc($1);
               say "Found header for: $value_type in ".$token->as_is;

			# Weed out values from other vehicles that appear on the same page
			if (defined $details_hash->{$value_type}) {
                    say "We've seen this detail on this vehicle already...must be looking at other 'similar' vehicles on page...quitting";
				last DETAILSLOOP;
			}

			$token = $vehiclepageparser->get_token;
			until ($token->is_start_tag('span') and $token->get_attr('class') eq 'value') {
				$token = $vehiclepageparser->get_token;
				if ($token == undef) {
                         say "Fell out of details loop before retrieving [$value_type] for this vehicle!";
					last DETAILSLOOP;
				}
			}
               $token = $vehiclepageparser->get_token;
			$value = $token->as_is;
               $value =~ s/\n//g;
			chomp($value);
			$details_hash->{$value_type} = $value;
			if ($value_type =~ /vin/i and $value =~/\w{17}/) {
                    say "VIN: [$value]";
			     say $token->as_is;
				DecodeVin($value, $details_hash);
				last DETAILSLOOP;
			}
		}
          elsif ($token->as_is eq 'Detailed Specifications') {
               say "End of detail on vehicle";
               last DETAILSLOOP;
          }
	}

	$value_type = 'Carfax link';
	while ($token = $vehiclepageparser->get_token) {
		if ($token == undef) {
			return ($details_hash);
		}
		elsif ($token->is_start_tag('div')) {
			if ($token->get_attr('class') =~ /carfaxfree/i) {
				$token = $vehiclepageparser->get_token;
				until ($token->is_start_tag('a')) {
					$token = $vehiclepageparser->get_token;
				}
				$value = $token->get_attr('href');
				$details_hash->{'carfax'} = $value;
			}
		}
	}
     say "Exiting ParseVehicleHTML";
	return ($details_hash);
}


=head2 DecodeVin()

Parses VIN data and outputs decoded information.

=cut

sub DecodeVin {
	my $vin_input = shift;
	my $details_hash = shift;

	my $restraint_types = {
		'[A-F]' =>'Active Belts (A.S.P.), Front Air Bags (O.S.P.), No Side Air Bags',
		'[G-M]' =>'Active Belts (A.S.P.), Front Air Bags (O.S.P.), Side Air Bags Front Row',
		'[N-U]' =>'Active Belts (A.S.P.), Front Air Bags (O.S.P.), Side Air Bags All Rows',
		'[VXYZ1-2]' => 'Active Belts (A.S.P.), No Air Bags',
		'[3-6]' =>'Active Belts (A.S.P.), Trucks over 10,000lbs GVWR',
		'W'	 =>'Incomplete Vehicles With Hydraulic Brakes',
	};


	my $vindata_by_position = {
		'1'		=>{
						'description' => 'Country of Origin',
							'1'	=> 'U.S.',
							'2'	=> 'Canada',
							'3'	=> 'Mexico',
						 },
		'2'	 =>{
						 'description' => 'Make',
						 'A' => 'Chrysler',
						 'B' => 'Dodge',
						 'D' => 'Dodge',
						 'C' => 'Ram',
						 'J' => 'Jeep',
					 },
		'3'	 =>{
						 'description' => 'Vehicle Type',
						 '3' => 'Truck',
						 '4' => 'Multipurpose Passenger Vehicle',
						 '5' => 'Truck',
						 '6' => 'Truck',
						 '7' => 'Truck',
						 '8' => 'Multipurpose Passenger Vehicle',
					 },
		'4'	 =>{
						 'description' => 'GVWR',
						 'A|G|N|V'=> 'GVWR = 4001-5000#',
						 'B|H|P|X'=> 'GVWR = 5001-6000#',
						 'C|J|R|Y'=> 'GVWR = 6001-7000#',
						 'D|K|S|Z'=> 'GVWR = 7001-8000#',
						 'E|L|T|1'=> 'GVWR = 8001-9000#',
						 'F|M|U|2'=> 'GVWR = 9001-10000#',
						 '3'		=> 'GVWR = 10001-14000#',
						 '4'		=> 'GVWR = 14001-16000#',
						 '5'		=> 'GVWR = 16001-19500#',
						 '6'		=> 'GVWR = 19501-26000#',
						 'W'		=> 'Incomplete Vehicle, GVRW Determined by downstream manufacturer',
					 },
		'5'	 =>{
						 'description' => 'Model Line and Vehicle Family',
						 'Truck' => {
									 '3' => 'Ram Chassis Cab (4x4) "DX" Family',
									 '5' => 'Ram Pickup Light Duty (4x2) "DX" Family',
									 '6' => 'Ram Pickup Light Duty (4x4) "DX" Family',
									 'U' => 'Ram Pickup Light Duty (4x4) "DR" Family',
									 'B' => 'Ram Pickup Light Duty (4x2) "DS" Family',
									 'C' => 'Ram Chassis Cab (4x2) "DM" Family',
									 'D' => 'Ram Chassis Cab (4x4) "DM" Family',
									 'E' => 'Dakota 4x2 "ND" Family',
									 'G' => 'Ram Chassis Cab (4x2) "DC" Family',
									 'H' => 'Ram Chassis Cab (4x4) "DC" Family',
									 'L' => 'Ram Pickup Heavy Duty (4x2) "D1" Family',
									 'N' => 'Ram Chassis Cab (4x2) "DX" Family',
									 'R' => 'Ram Pickup Heavy Duty (4x2) "DH" Family',
									 'S' => 'Ram Pickup Heavy Duty (4x4) "DH" Family',
									 'V' => 'Ram Pickup Light Duty (4x4) "DS" Family',
									 'W' => 'Dakota 4x4 "ND" Family',
									 'X' => 'Ram Pickup Heavy Duty (4x4) "D1" Family',
									 },
						 'MPV' => {
									 'G' => 'Journey Left Hand Drive, Front Wheel Drive "JC" Family',
									 'H' => 'Journey Left Hand Drive, All Wheel Drive "JC" Family',
									 '5' => 'Journey Right Hand Drive, Front Wheel Drive "JC" Family',
									 'T' => 'Nitro Left Hand Drive, 4x2 "KA" Family',
									 'U' => 'Nitro Left Hand Drive, 4x4 "KA" Family',
									 '9' => 'Nitro Right Hand Drive, 4x4 "KA" Family',
									 'R' => 'Town & Country Left Hand Drive, Front Wheel Drive "RT" Family',
									 'S' => 'Grand Voyager Left Hand Drive, Front Wheel Drive "RT" Family',
									 'T' => 'Grand Voyager Right Hand Drive, Front Wheel Drive "RT" Family',
									 'S' => 'Grand Voyager Left Hand Drive, Front Wheel Drive "RT" Family',
									 },
					 },
		'6'	 =>{
						 'description' => 'Series/Price Class',
						 'Truck' => {
									 '1' => '1500',
									 '2' => '2500',
									 '3' => '3500 Less DRW',
									 '4' => '3500 DRW',
									 '5' => '4000 DWR',
									 '6' => '4500 DWR',
									 '7' => '5500 DWR',
									 },
						 'MPV' => {
									 '1' => 'E (Economy)',
									 '2' => 'L (Low Line)',
									 '3' => 'M (Medium)',
									 '4' => 'H (High Line)',
									 '5' => 'P (Premium)',
									 '6' => 'S (Sport)',
									 '7' => 'X (Special)',
									 },
					 },
		'7'	=>{
						 'description' => 'Body Style by Vehicle Line',
						 'Dakota' =>
									 {
										 '2' => 'Extended Cab / Dakota Pickup',
										 'B' => 'Extended Cab / Dakota Pickup',
										 'G' => 'Crew Cab / Dakota Pickup',
										 '8' => 'Crew Cab / Dakota Pickup',
									 },
						 'Ram' =>
									 {
										 '3' => 'Crew Cab',
										 'C' => 'Crew Cab',
										 '8' => 'Quad Cab',
										 'G' => 'Quad Cab',
										 '6' => 'Regular Cab/Chassis',
										 'E' => 'Regular Cab/Chassis',
										 'H' => 'Mega Cab',
									 },
						 'MPV'	 =>
									 {
										 '1' => 'Extended Van Grand Caravan C/V',
										 '4' => 'Extended Van Grand Caravan, Voyager T&C',
										 'A' => 'Extended Van Grand Caravan C/V',
										 '7' => 'Hatchback Tall / Journey Body Style',
										 'F' => 'Hatchback Tall / Journey Body Style',
										 'G' => 'Sport Utility 4 Door',
										 '8' => 'Sport Utility 4 Door',
										 'D' => 'Extended Wagon,Grand Caravan/Voyager T&C',
									 },
					 },
		'8' =>{
				'description' => 'Engine',
				'2' => '5.7L 8CYL Mul Disp Gasoline (EZB)',
				'C' => '1.8L 4CYL Gasoline Non-Turbo (EBA)',
				'Y' => '2.0L 4CYL Diesel(ECD, ECE)',
				'A' => '2.0L 4CYL Gasoline Non-Turbo (ECN, ECP)',
				'A' => '2.0L 4CYL Gaoline/CNG Non-Turbo (ECQ)',
				'U' => '2.2L 4CYL Diesel (ENE)',
				'B' => '2.4L 4CYL Gasoline Non-Turbo (EDG, ED3)',
				'F' => '2.4L 4CYL Gasoline Turbo (ED4)',
				'D' => '2.7L 5CYL Gasoline Non-Turbo (EER)',
				'5' => '2.8L 4CYL Diesel (ENS)',
				'M' => '3.0L 6CYL Diesel (EXL)',
				'E' => '3.3L 6CYL Gasoline Non-Turbo (EGV)',
				'V' => '3.5L 6CYL Gasoline Non-Turbo (EGF, EGG)',
                    'G' => '3.6L 6CYL Gasoline Non-Turbo',
				'K' => '3.7L 6CYL Gasoline Non-Turbo (EKG)',
				'K' => '3.7L 6CYL Gasoline/CNG Non-Turbo (EKH)',
				'1' => '3.8L 6CYL Gasoline Non-Turbo (EGL, EGT)',
				'X' => '4.0L 6CYL Gasoline Non-Turbo (EGQ, EGS)',
				'P' => '4.7L 8CYL Gasoline Non-Turbo (EVE)',
				'T' => '5.7L 8CYL Gasoline Non-Turbo (EZC, EZE, EZH)',
				'W' => '6.1L 8CYL Gasoline Non-Turbo (ESF)',
				'J' => '6.4L 8CYL Gasoline (ESG, ESH)',
				'L' => '6.7L 6CYL Diesel (ETJ)',
				'Z' => '8.4L 10CYL Gasoline Non-Turbo (EWE)',
				},
		'9'=>{
					'description' => 'Check Digit',
					},
		'10' =>{
					'description' => 'Model Year',
					'Y' => '2000', '8' => '2008', 'G' => '2016', 'R' => '2024',
					'1' => '2001', '9' => '2009', 'H' => '2017', 'S' => '2025',
					'2' => '2002', 'A' => '2010', 'J' => '2018', 'T' => '2026',
					'3' => '2003', 'B' => '2011', 'K' => '2019', 'V' => '2027',
					'4' => '2004', 'C' => '2012', 'L' => '2020', 'W' => '2028',
					'5' => '2005', 'D' => '2013', 'M' => '2021', 'X' => '2029',
					'6' => '2006', 'E' => '2014', 'N' => '2022',
					'7' => '2007', 'F' => '2015', 'P' => '2023'},
		'11' =>{
					'description' => 'Assembly Plant',
					'A'=> 'Chrysler Technical Center Pre-Production & Pilot',
					'C'=> 'Jefferson North Assembly',
					'D'=> 'Belvidere Assembly',
					'E'=> 'Saltillo Van/Truck Assembly Plant',
					'G'=> 'Saltillo Truck Assembly Plant',
					'H'=> 'Brampton Assembly',
					'J'=> 'St. Louis Assembly North',
					'L'=> 'Toledo South Assembly',
					'N'=> 'Sterling Heights Assembly',
					'R'=> 'Windsor Assembly',
					'S'=> 'Warren Truck Assembly',
					'T'=> 'Toluca Assembly',
					'W'=> 'Toledo North Assembly',
					},
	};

	say "Processing [$vin_input]";
	my @vin_chars = (split(//, $vin_input));
	my $position = 1;
	my $serial_number;
	my $is_truck = FALSE;
	my $is_ram = FALSE;
	my $is_dak = FALSE;
	my $is_mpv = FALSE;
	my $year = $vindata_by_position->{'10'}{$vin_chars[9]};
	say "Year: $year";

	foreach my $vin_char (@vin_chars) {
		my $description = $vindata_by_position->{$position}{'description'};
		my $value;
		if ($position == 4) {
			foreach my $key (keys($vindata_by_position->{$position})) {
				if ($vin_char =~ /$key/) {
					 $value = $vindata_by_position->{$position}{$key};
				}
			}
			foreach my $key (keys(%$restraint_types)) {
				if ($vin_char =~ /$key/) {
					$details_hash->{'VIN_Restraints'} = $restraint_types->{$key};
				}
			}
		}
		elsif ($position < 4 or ($position > 7 and $position != 12 and $position != 9)) {
			$value = $vindata_by_position->{$position}{$vin_char};
			if ($value eq 'Truck') {
				$is_truck = TRUE;
			}
		}
		elsif ($position == 5 or $position == 6) {
			my $href = ($is_truck == TRUE) ? $vindata_by_position->{$position}{'Truck'} :
											$vindata_by_position->{$position}{'MPV'};
			$value = $href->{$vin_char};
			if ($position == 5 and $value =~ /RAM/i) {
				$is_ram = TRUE;
			}
			elsif ($position == 5 and $value =~ /DAK/i) {
				$is_dak = TRUE;
			}
			elsif ($position == 5 and $value !~ /RAM|DAK/) {
				$is_mpv = TRUE;
			}
			if ($year <= 2012) {
				if ($position == 5 and $value =~ /4x4|AWD/) {
					$details_hash->{'Is_4WD'} = 1;
				}
				elsif ($position == 5 and $value !~ /4x4|AWD/) {
					$details_hash->{'Is_4WD'} = 0;
				}
			}
			elsif ($year == 2012) {
				if ($position == 6 and (($value % 2) == 1)) {
					$details_hash->{'Is_4WD'} = 1;
				}
				elsif ($position == 6 and (($value % 2) == 0)) {
					$details_hash->{'Is_4WD'} = 0;
				}
			}
		}
		elsif ($position == 7) {
			my $href;
			$is_ram and $href = $vindata_by_position->{$position}{'Ram'};
			$is_dak and $href = $vindata_by_position->{$position}{'Dakota'};
			$is_mpv and $href = $vindata_by_position->{$position}{'MPV'};
			$value = $href->{$vin_char};
		}
		elsif ($position == 9) {
			$value = $vin_char;
		}
		elsif ($position == 12) {
			$value = substr($vin_input, 11);
			$details_hash->{'vin_serial'} = $value;
			last;
		}
		$position++;
		$details_hash->{'VIN_' . $description} = $value;
          say "VIN_$description = $value";
	}
	return;
}


=head2 Calculate_Check_Digit()

Computes a standard VIN check digit from the VIN,
and matches it up to the check digit in the 9th position.

Returns TRUE if the check digit is correct, FALSE otherwise.

=cut

sub Calculate_Check_Digit {
	my $vin_input = shift;

	my $transliterate = {
							'A' => 1, 'B' => 2, 'C' => 3,
							'D' => 4, 'E' => 5, 'F' => 6,
							'G' => 7, 'H' => 8, 'J' => 1,
							'K' => 2, 'L' => 3, 'M' => 4,
							'N' => 5, 'P' => 7, 'R' => 9,
							'S' => 2, 'T' => 3, 'U' => 4,
							'V' => 5, 'W' => 6, 'X' => 7,
							'Y' => 8, 'Z' => 9};

	my @weights = qw(8 7 6 5 4 3 2 10 0 9 8 7 6 5 4 3 2);

	my @vin_chars = (split(//, $vin_input));

	my $vin_check_digit = $vin_chars[8];

	my $weightpos = 0;
	my $sum = 0;

	foreach my $char (@vin_chars) {
		my $val;
		if ($char =~ /[0-9]/) {$val = $char;}
		else {$val = $transliterate->{$char};}
		$sum += $val * $weights[$weightpos++];
	}

	my $calc_check_digit = $sum % 11;

	if ($calc_check_digit == 10) {$calc_check_digit = 'X';}

	if ($calc_check_digit eq $vin_check_digit) {
		return TRUE;
	}
	return FALSE;
}