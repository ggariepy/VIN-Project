#!C:\Perl\bin\perl.exe
use Dancer;
use VinDatabase::RamTrucks;
use Dancer::Plugin::Database;
use Dancer::Plugin::SimpleCRUD;

my $vehicle_dbh = database('vehicle');
my $vin_dbh = database('vin');

get '/entervins' => sub {
  my $sql = 'select Description from Vehicle_Types order by Description asc';
  my $sth = $vin_dbh->prepare($sql) or die $vin_dbh->errstr;
  $sth->execute or die $sth->errstr;
  template 'vin_db_editor.tt', { 
     'vehicletypes' => $sth->fetchall_arrayref(),
  };
};

simple_crud(
   record_title => 'Dealership',
   prefix => '/dealerships',
   db_table => 'Dealership',
   editable => 1,
   key_column => 'Dealership_ID',
   db_connection_name => 'vehicle',
   sortable => 1,
);
dance;