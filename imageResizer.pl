#!/usr/bin/perl
use Modern::Perl;
use File::Find qw/find/;
use File::Spec;
use File::Path qw/mkpath/;
use Cwd        qw/cwd/;
use Image::Magick;
use Time::Piece;
# #Will also use command "exiv2" if found
# my $exiv2Path = "/usr/bin/exiv2";

#options
my $debug=0;
#TODO: move to command line options
my $dirToProcess = "Photos";
# WxH
#TODO: move to command line options
my @outputMinSizes = qw( 1280x800 );
#my @outputMinSizes = qw( 1280x800 480x320 );
#end options

my $summary_hashref = {};
my $msgfmt = "%-10s: %s\n";
my $basedir = cwd()."/".$dirToProcess;
my $currentOutputSize;
foreach (@outputMinSizes)
{
  $currentOutputSize = $_;
  print "==== $currentOutputSize ====\n";
  print "== Checking for new files ==\n";
  find( {wanted=>\&process_file, no_chdir=>1} , $basedir );
  print "== Removing deleted files ==\n";
  find( {wanted=>\&remove_deleted_file, no_chdir=>1}, $currentOutputSize);
}

my $summary_string = "";
my $changes_made = 0;
foreach my $size (keys %$summary_hashref)
{
  $summary_string .= "Size: $size:\n";
  foreach my $type (keys %{$summary_hashref->{$size}})
  {
    $summary_string .= "  $type: ".$summary_hashref->{$size}->{$type}."\n";
  }
  if( $summary_hashref->{$size}->{new} || $summary_hashref->{$size}->{deleted} )
  { 
    my $changes_made = 1;
  }
}
warn $summary_string if $changes_made;
print $summary_string unless $changes_made;

sub remove_deleted_file
{
  my $f = $File::Find::name;

  return unless -f $f;

  my $s = $f;
  $s =~ s|^\/?\d+\/||;
  $s = "$basedir/$s";
  #skip files if the source ($s) still exists
  return if -f $s;

  warn sprintf $msgfmt, "rm", "'$f'";
  unlink $f || warn "error removing $f, $!";
  $summary_hashref->{$currentOutputSize}->{deleted}++;
}

sub process_file 
{
  my $f = $File::Find::name;
  my $outputFileName;

  return if $basedir eq $f;

  if( $f =~ m!^$basedir/(.+)! )
  {
    $outputFileName = cwd()."/$currentOutputSize/$1";
  }
  else
  {
    warn "not sure what to do with path '$f'\n";
    return;
  }

  return unless $f =~ /\.jpg$/i;

  my($atime,$mtime) = (stat($f))[8,9];

  my $outputDir = ( File::Spec->splitpath($outputFileName) )[1];
  if( ! -d $outputDir )
  {
    warn sprintf $msgfmt, "mkdir", "'$outputDir'";
    mkpath($outputDir) || warn "ERROR making dir '$outputDir', $!\n";
  }

  #new image if it doesnt exist or is older than our source
  if( ! -e $outputFileName || $mtime > (stat($outputFileName))[9] )
  {
# Get timestamp of photo from exif so we can use it to set the file age on disk
# Not sure yet if i really want this - if we dont use it and set the timestamp to
# the same as the origina file then we can test the timestamps to see if the source file
# has been edited or updated, and rebuild
#     if( -e $exiv2Path )
#     {
#       my $exiv2Output = `exiv2 $f`;
#       #Image timestamp : 2011:06:10 06:57:41
#       if($exiv2Output =~ /Image timestamp\s*:\s*([\d\:]+\s[\d:]+)/ )
#       {
#         my $time = Time::Piece->strptime($1, "%Y:%m:%d %H:%M:%S");
#         $time += $time->localtime->tzoffset;
#         print $time->epoch()."\n";
#         $atime = $mtime = $time->epoch();
#       }
#     }
    my $im = new Image::Magick;
    my $err = $im->Read($f);
    if($err)
    {
      print "error    \t$f\n";
      print $err;
      return;
    }
    my $w = $im->get('width');
    my $h = $im->get('height');
    my ($currentOutputWidth,$currentOutputHeight) = split(/x/,$currentOutputSize);
    my $smallest_side = ($w<$h) ? $w : $h;

    # use RESxRES> to only shrink larger images. This should mean we fit within the 
    # supplied res
    my $newsize = ($w >= $h) ? $currentOutputWidth ."x".$currentOutputHeight.">" 
                             : $currentOutputHeight."x".$currentOutputWidth .">" ;
    #print "$w x $h ->$newsize - $f\n";
    warn sprintf $msgfmt, "new","'$outputFileName'";
    $err = $im->Resize(geometry => $newsize);
    warn sprintf $msgfmt, "ERROR", $err if $err;
    $summary_hashref->{$currentOutputSize}->{new}++;

    $err = $im->Write($outputFileName);
    warn sprintf $msgfmt, "ERROR", $err if $err;
    utime $atime, $mtime, $outputFileName;
  }
  #otherwise the file exists already and is as old as our smaller image
  else
  {
    printf $msgfmt, "exists", "'$outputFileName'";
    $summary_hashref->{$currentOutputSize}->{unchanged}++;
  }
}
