#!/usr/bin/perl
use Modern::Perl;
use File::Find qw/find/;
use File::Spec;
use File::Path qw/mkpath/;
use Cwd        qw/cwd/;
use Image::Magick;
use Time::Piece;
use Getopt::Long;
use Pod::Usage;

my ($debug,$input,$outputBase,@outputMinSizes,$help,$man);
my $result = GetOptions ("input|i=s"             => \$input,
                         "output|outputBase|o=s" => \$outputBase,
                         "size=s"                => \@outputMinSizes,
                         "verbose|v"             => \$debug,
                         "help|h|?"              => \$help, 
                         "man"                   => \$man,
                        ) or pod2usage(2);
pod2usage(-exitstatus => 1, -verbose => 1) if $help;
pod2usage(-exitstatus => 1, -verbose => 2) if $man;
#Show help if options missing
help("input flag is required") unless $input;
help("output flag is required") unless $outputBase;
help("size flag is required") unless @outputMinSizes;


#Tidy initial paths, remove trailing slash
$input =~ s|/$||;
$outputBase =~ s|/$||;


# #Will also use command "exiv2" if found
# my $exiv2Path = "/usr/bin/exiv2";
foreach (@outputMinSizes)
{
  die "size must be NNNxNNN" unless /^\d+x\d+$/i;
}

my $summary_hashref = {};
my $msgfmt = "%-10s: %s\n";
my $basedir = $input;
my $currentOutputSize;
foreach (@outputMinSizes)
{
  $currentOutputSize = $_;
  print "==== $currentOutputSize ====\n";
  print "== Checking for new files ==\n";
  find( {wanted=>\&process_file, no_chdir=>1} , $basedir );
  print "== Removing deleted files ==\n";
  find( {wanted=>\&remove_deleted_file, no_chdir=>1}, "$outputBase/$currentOutputSize");
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
  #skip files if the source ($s) still exists
  return if -f $s;

  warn sprintf $msgfmt, "rm", "'$f'";
  unlink $f || warn "error removing $f, $!";
  $summary_hashref->{$currentOutputSize}->{deleted}++;
}

sub process_file 
{
  our $verbose;
  my $f = $File::Find::name;
  my $outputFileName;

  return if $basedir eq $f;

  if( $f =~ m!^$basedir/(.+)! )
  {
    $outputFileName = "$outputBase/$currentOutputSize/$1";
  }
  else
  {
    print "\$f:       $f\n";
    print "\$basedir: $basedir\n";
    warn "not sure what to do with path '$f'\n";
die;
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
    printf $msgfmt, "exists", "'$outputFileName'" if $verbose;;
    $summary_hashref->{$currentOutputSize}->{unchanged}++;
  }
}


sub help
{
  my $msg = shift;
  pod2usage(-msg  => $msg, -exitval => 2, -verbose => 1);
}
=head1 NAME

imageResizer.pl help

=head1 SYNOPSIS

imageResizer.pl -input <dir> -output <dir> -size <WxH> [-size <WxH>,..] [-verbose]

=head1 OPTIONS

=over 8

=item B<-input|i> path

The input directory to scan for folders of photos.

=item B<-output|outputBase|o> path

The directory to write the output into

=item B<-size|s> NNNxNNN

"Shrinks images with dimension(s) larger than the corresponding width and/or height dimension(s)."

This flag can be supplied multiple times for multiple output sizes

=item B<-verbose|v>

Be more verbose about what is being done

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits. 

=back

=head1 DESCRIPTION

B<imageResizer.pl> takes a source tree of images, an output dir, and an array of image sizes.
It loops over each size supplied and generates a new tree of images all of which have the smallest
matching the supplied sizes.

The actual resize is an imagemagick Resize operation to the supplied geometry and 
a "larger than" adjustment, i.e. WxH>

=cut
