use REST::Client;
use warnings;
use Data::Dumper;
use Data::Dump qw(dump);
use JSON;
use MIME::Base64;
use strict;
use LWP::UserAgent;

my @time = localtime(time);
my $timesuffix = $time[2].":".$time[1].":".$time[0]."_".$time[7]."-".$time[4]."-".$time[5];

our $username;
our $password;
our $cachefile = "confluence_data.hash";
our $comparefile;
our $outfile = "confluence_data_" . $timesuffix .".hash";
our $tinyfile = "confluence_shortel_tiny_map.hash";
our $url = "https://<REDACTED>.<REDACTED>.com";
our $rebuildTiny = 0;
my $limit;#limit on number of items to get, passed into retrieve func
my $cacheFlag = 1;#whether or not to use cached data, true by default
my $update_flag = 0;
our $oldFlag = 0;
our $getAll = 1;#flag to get all elements thru repeated API calls each of size $limit, true by default
our $updated_pages_file = "updated_pages";
#need username / password from CLI args
if (@ARGV < 2){
	#do nothing, skip arg handling unless at least 2 args
}
# if (@ARGV == 2){
	# $username = $ARGV[0];
	# $password = $ARGV[1];
	# $limit = 500;
# }
# elsif (@ARGV == 3){
	# $username = $ARGV[0];
	# $password = $ARGV[1];
	# $limit = $ARGV[2];
# }
else{
	#READ ME!!!!
	#Non switch parameters require a followup value, but I do not sanitize for those
	#so, ex: calling >script.pl -u -g will set $username="-g"
	#also, calling without followup arg like this: >script.pl -u 
	#will cause array index out of range, so have fun with that
	for (my $i =0; $i < @ARGV; $i++){
		if ($ARGV[$i] eq '-u'){
			$username = $ARGV[++$i];
			chomp($username);
			$username =~ s/"//g;
		}#-u username
		elsif ($ARGV[$i] eq '-p'){
			$password = $ARGV[++$i];
			chomp($password) if ($password);
			$password =~ s/"//g;
		}#-p password
		elsif ($ARGV[$i] eq '-l'){ $limit = $ARGV[++$i]; }#-l limit
		elsif ($ARGV[$i] eq '-api'){ $cacheFlag = 0; }#-cf is disable cache flag
		elsif ($ARGV[$i] eq '-g'){ $getAll = 0; }#-g is disable get all, meaning only do 1 api call for size $limit
		elsif ($ARGV[$i] eq '-old'){
			$url = "https://wiki.<REDACTED>.com";
			$oldFlag = 1;
		}#-g is disable get all, meaning only do one api call for size $limit
		elsif ($ARGV[$i] eq '-cf'){
			$cachefile = $ARGV[++$i];
			chomp($cachefile);
		}#-cf <file name of existing cache file you want to read from>
		elsif ($ARGV[$i] eq '-out'){
			$outfile = $ARGV[++$i];
			chomp($outfile);
		}#-out <file name of cache file for new api call> #requires -api option specified to actually work
		elsif ($ARGV[$i] eq '-rbt'){
			$rebuildTiny = 1;
		}
		elsif ($ARGV[$i] eq '-put'){
			$update_flag = 1;
		}
		elsif ($ARGV[$i] eq '-cmp'){
			$comparefile = $ARGV[++$i];
			chomp($cachefile);
		}
		else {
			print "Invalid argument '$ARGV[$i]'\n";
			exit 1;
		}#fail on unknown parameter
	}
}

our %pages;#hash of PageID->PageTitle
our %compare_pages;
our %tiny;#contains the map of tiny urls to page names
our %map;#contains the mapping of tinyurls-><REDACTED> Wiki Page IDs
our $headers = {'Content-Type'=>'application/json','Authorization'=>'Basic ' . encode_base64($username.':'.$password)};#json return headers
our $client = REST::Client->new();
$client->setHost($url);
our %ignore_pages;
load_updated_pages();

print "Running with parameters:\n";
print "User: $username\n" if ($username);
print "URL: $url\n";
print "Output File: $outfile\n" if ($outfile);
print "Cache File: $cachefile\n" if ($cachefile);
print "GetAll Flag: $getAll\n";
print "API Flag: $cacheFlag\n";
print "Limit: $limit\n" if ($limit);
print "CacheFlag = $cacheFlag\n";
print "\n";

system("pause");

#two methods of retrieving data: Cached Data or new API calls
#API is slow, cache is always updated on new API calls
if($cacheFlag){#lookup cached data from previous api call, reads into %pages
	if (cached_lookup() != 0){
		print "Cached_lookup() failed.\n";
		exit 1;
	}
	if ($comparefile){
		if (cached_lookup_compare() != 0){
			print "Cached_lookup() failed.\n";
			exit 1;
		}
		else{
			my %compare_list;
			print "Number of pages: " . scalar(keys %pages) . "\n";
			print "Number of CMP pages: " . scalar(keys %compare_pages) . "\n";
			foreach my $page (keys %pages){
				$compare_list{$pages{$page}->{title}} = 2;
				#print $pages{$page}->{title} . "\n";
			}
			foreach my $page (keys %compare_pages){
				$compare_list{$compare_pages{$page}->{title}}++;
				#print $compare_pages{$page}->{title} . "\n";
			}
			print "Number of compare_list: " . keys(%compare_list) . "\n";
			foreach my $page (keys %compare_list){
				#print $compare_list{$page} . "\n";
				if ($compare_list{$page} == 2){
					print "($cachefile) " . $page . "\n";
				}
				elsif ($compare_list{$page} == 1){
					print "($comparefile) " . $page . "\n";
				}
			}
			exit 0;
		}
	}
}
elsif (1){#get new data from api
	my $status = retrieve($limit);
	if ($status){
		print "Whoops: Something went wrong\n$status\n";
		exit 1;
	}
	
	open(OUT,">",$outfile) or die "Failed to open output file: $!\n";
	#foreach my $key (keys %pages){ print $key . " = ". $pages{$key}->{title} . "\n"; }
	print OUT (dump(\%pages));
	close OUT;
}
else{#catch a screwup :)
	print "Well you do kinda have to do one of the two. That's all this script is meant to do...\n";
	exit 1;
}

#%pages should be loaded at this point and contains all data retrieved from last successful API call
print "Number of Pages: " . scalar(keys %pages) . "\n";#print # of pages found

#only rebuild on request, others load from file
if($rebuildTiny == 1){
	build_tiny_url_map();
	exit 2;
}
else{
	read_tinyui_map();
}

die;

############
#examples###
#page title: $pages{ <PageID> }->{title};
#page Body:  $pages{ <PageID> }->{body}->{view}->{value};
#page IDs:   keys(%pages)
############

if ($oldFlag == 1){
	exit 2;
}

my $countTiny = 0;
my $countFull = 0;
my $countExt = 0;
my $replace;
my %update_pages;#contains the pages that have been updated, surpressed dups
foreach my $page (keys %pages){
	my @matches;#contains a list of the global matches for urls in wiki page bodies
	if (@matches = $pages{ $page }->{body}->{view}->{value} =~ m#https?\:\/\/wiki\.<REDACTED>\.com[^\ "<]*#ig){
		foreach my $match (@matches){
			next if ($match =~ m#\.png$#);#ignore picture references for now
			#print "[$page]" . " $pages{$page}->{title}" . "-> " . $match . "\n";
			#print $pages{$page}->{body}->{view}->{value} . "\n"
			$replace = "https://<REDACTED>.<REDACTED>.com/wiki/display/<REDACTED>/";
			my $tinyCheck = $match =~ m#https?://wiki.<REDACTED>.com(/x/[\-a-zA-Z0-9_]+)#;
			if ($tinyCheck and $tiny{$1}){#short link && known equivalent
				$replace .= $tiny{$1};
				$replace =~ s#,#%2C#g;
				chomp($replace);
				$replace=~s#\ #\+#g;#convert spaces to '+' per wiki standard
				$pages{ $page }->{body}->{view}->{value} =~ s#$match#$replace#;#replace matched url for replaced url in page body content
				$countTiny++;
				$update_pages{$page}++;
			}
			elsif ($tinyCheck){
				#print "Resolving: $match -> ";
				my $redir = resolveRedirct($match);
				#print "$redir\n";
				next unless ($redir);
				next if ($redir =~ m#<REDACTED>\.okta\.com/login#);
				$replace =~ s#,#%2C#g;
				$redir =~ m#display/(.+)$#;
				$replace = "https://<REDACTED>.<REDACTED>.com/wiki/display/" . $1;
				$pages{ $page }->{body}->{view}->{value} =~ s#$match#$replace#;#replace matched url for replaced url in page body content
				$countTiny++;
				$update_pages{$page}++;
			}
			elsif ($match=~m#/display/(.*)# ){
				$replace .= "/" . $1;
				$replace =~ s#,#%2C#g;
				$pages{ $page }->{body}->{view}->{value} =~ s#https://wiki.<REDACTED>.com/display/#https://<REDACTED>.<REDACTED>.com/wiki/display/# ;
				$countFull++;
				$update_pages{$page}++;
			}
			elsif ($match =~ m#viewpage\.action\?pageId\=([0-9]+)#){
				no warnings 'uninitialized';
				#print $pages{ $page }->{body}->{view}->{value} . "\n";
				foreach my $BAD (keys %pages){
					if ($pages{$BAD}->{title} eq $tiny{$1}){
						my $one = $pages{$BAD}->{id};
						$pages{ $page }->{body}->{view}->{value} =~ s#$match#https://<REDACTED>.<REDACTED>.com/wiki/pages/viewpage.action?pageId=$one#;
					}
				}
				$update_pages{$page}++;
				#print $pages{ $page }->{body}->{view}->{value} . "\n\n";
			}
			else{
				$countExt++;
				next;#skips changing wiki for links that could not be resolved
			}
			#print "[$match] => [$replace]\n";
			
			#print $pages{$page}->{body}->{view}->{value} . "\n";#prints entire page body, very big
			#system("pause");
		}
	}
}

print "\n";

if (1){
	#pass through again and detected links
	my $count;
	foreach my $page (keys %pages){
		if ($pages{ $page }->{body}->{view}->{value} =~ m#https?\:\/\/wiki\.<REDACTED>\.com[^\ "<]*#ig){
			#print "FAILED: $&\n";
			$count++;
		}
	}
	print "# of Unqiue Pages: " . (keys(%update_pages)) . "\n";
	print "# of Failed Links: $count\n";
	print "# of Tiny Links: $countTiny\n";
	print "# of Full Links: $countFull\n";
	print "# of External Links: $countExt\n";
}

foreach my $page (keys %update_pages){
	print "https://<REDACTED>.<REDACTED>.com/wiki/pages/viewpage.action?pageId=$page\n";
}
die;

my $update_status = -1;#initialize to -1 incase -put flag not specified
foreach my $page (keys %update_pages){
	if ($ignore_pages{$page}) { print "Skipping $page, already editted\n"; next; }
	my $x = 'https://<REDACTED>.<REDACTED>.com/wiki/pages/viewpage.action?pageId=' . $page;
	print $x . "\n";
	
	if ($update_flag){
		$update_status = update($page);
	}
	if ($update_status == 0){
		system('"c:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe" ' . $x);
	}
	
	print "Continue[Yn] ";
	my $y = <STDIN>;
	if ($y=~m/n/i){
		die "Oops\n";
	}
}

exit 0;#code is done
########################################################################################################

sub load_updated_pages{
	open (IN,"<",$updated_pages_file) or return;
	my $x;
	while ($x = <IN>){
		chomp($x);
		$ignore_pages{$x}=1;
	}
	close IN;
	return;
}

sub build_tiny_url_map{
	#local $/;#I dont know what this does, but the code fails without it
	if (keys %pages == 0) { return 1; }
	#%pages keys are both /x/abcdef AND <pageID>
	#both = the corresponding page name
	foreach my $page (keys %pages){
		#print "$page: " . $pages{$page}->{title} . "\n";
		#print $pages{$page}->{_links}->{tinyui} . " : " . $pages{$page}->{title} . "\n";
		$tiny{ $pages{$page}->{_links}->{tinyui} } = $pages{$page}->{title};#builds in memory as well, cache reader will do only this line
		$tiny{ $page } = $pages{$page}->{title};#builds in memory as well, cache reader will do only this line
	}
	open(OUT, ">", $tinyfile) or die "Failed to create tinyui map: $!\n";
	print OUT (dump(\%tiny));
	close OUT;
	return;
}

sub read_tinyui_map{
	local $/;
	open(my $in, "<", $tinyfile) or die "Failed to create tinyui map: $!\n";
	%tiny = %{ eval <$in> };
	close $in;
	return;
}

sub cached_lookup{
	local $/;#I dont know what this does, but the code fails without it
	open (my $in,"<",$cachefile) or (return "Cannot open $cachefile");
	%pages = %{eval <$in>};#read the dump data in %pages as it was when originally gathered from server
	close $in;
	return 0;
}

sub cached_lookup_compare{
	local $/;#I dont know what this does, but the code fails without it
	open (my $in,"<",$comparefile) or (return "Cannot open $cachefile");
	%compare_pages = %{eval <$in>};#read the dump data in %pages as it was when originally gathered from server
	close $in;
	return 0;
}

sub resolveRedirct(){
	my $x = shift @_;
	chomp($x);

	my $ua = LWP::UserAgent->new;#create LWP user agent
	$ua->ssl_opts(verify_hostname => 0, SSL_verify_mode => 0x00);#disable SSL verify
	my $req = HTTP::Request->new(GET => $x);#get request, all that is needed is the redirct url
	$req->header('Accept'=>'text/html');#header set

	my $res = $ua->request($req);#submit request

	if($res->is_success){#check status
		return $res->request()->uri();#return resolved redirect
	}
	
	return "";#if connection failed, return empty string
}

sub update{
	my $page = shift;
	my $reply;
	$reply->{version}->{number} = $pages{$page}->{version}->{number} + 1;
	$reply->{version}->{minorEdit} = 'false';
	$reply->{version}->{hidden} = 'false';
	$reply->{title} = $pages{$page}->{title};
	$reply->{type} = $pages{$page}->{type};
	$reply->{body}->{storage}->{value} = $pages{$page}->{body}->{view}->{value};
	$reply->{body}->{storage}->{representation} = $pages{$page}->{body}->{view}->{representation};
	$reply->{id} = $page;
	$reply->{status} = "current";
	#dump($reply);
	$reply = to_json($reply);
	#system('pause');
	
	#push the changes to wiki, requires the our $client to be setup in main code
	$client->PUT(
		"wiki/rest/api/content/$page",
		$reply,
		$headers,
	);
	if ($client->responseCode != 200){
		print "PUT response: " . $client->responseCode . "\n";
		print $client->responseContent();
		return 1;
	}
	{#print updated page IDs to tracking page so they are skipping next time (cache is not updated every time)
		open (OUT, ">>", "updated_pages") or die "Could not open tracking page for updated pages: $!\n";
		print OUT ($page . "\n");
		close OUT;
	}
	return 0;
}

sub retrieve{
	my $limit = shift;#integer limit to # of results
	if (!$limit or $limit <= 0) {$limit=10;}#you cannot have a negative limit, that's dumb and you thought I wouldn't check for it, but I did
	elsif ($limit > 500) {$limit=500;}#max return results is 500 on wiki server side, I can't change that so deal with it
	
	my $spacekey = '<REDACTED>';#confluence space name, case sensitive
	my $headers = {Accept=>'application/json',Authorization=>'Basic ' . encode_base64($username.':'.$password)};#json return headers
	my $client = REST::Client->new();
	
	# don't verify SSL certs for <REDACTED> wiki
	if ($url eq "https://wiki.<REDACTED>.com"){
		$client->getUseragent()->ssl_opts(verify_hostname => 0);                                                                        
		$client->getUseragent()->ssl_opts(SSL_verify_mode => "SSL_VERIFY_NONE");
	}
	
	$client->setHost($url);
	my $start = 0;#page to start at, 0 means it will get all pages in the space
	my $size = $limit;#set to $limit to force first loop iteration
	my $response;
	
	#loop while data is received, last GET if the returned size was under limit
	while ($size > 0){
		if ($url eq "https://wiki.<REDACTED>.com"){#call for old wiki format
			$client->GET(
				"/rest/api/space/<REDACTED>/content/page?limit=$limit&start=$start",
				$headers
			);#get all page data from spaceKey=<confluence space name> limit=<# returned results> start=<starting page, 0>
		}
		else{#call for new (<REDACTED>) wiki format
			$client->GET(
				"/wiki/rest/api/content?spaceKey=$spacekey&limit=$limit&start=$start&expand=body.view,version",
				$headers
			);#get all page data from spaceKey=<confluence space name> limit=<# returned results> start=<starting page, 0>
		}
		my $base_resp = $client->responseContent();#get response
		#print Dumper($base_resp);#unformated, raw data print
		eval{
			$response = from_json($base_resp);#json decode of REST API server response
		} or do {
			#return to caller with error and write a html file to ./<this directory> of the returned error page from REST server
			open (my $ERR,">","API_Error.html") or die "Failed to open error file lol. $!\n";
			print {$ERR} "$base_resp";
			close $ERR;
			return $@ . "\n" . $response if ($response);#try to send the decoded response
			return $@ . "\n" . $base_resp if ($base_resp);#alternatively, try to send raw response data
			return $@;#lastly, catch all return error info
		};
		
		#get the size of results returned and update next iteration start position
		my @results = @{$response->{results}};
		$size = $response->{size};
		$start += $size;
		
		foreach my $x (@results){
			#foreach my $k (keys(%$_)){ print $k . " "; }#shows all elements of contained within results field for each element (page)
			#print "\n";
			#print $x->{title} . "\n";#prints the title of each page to screen
			#push @pages,$x->{title};#save each page title in array, this doesn't keep IDs, so I removed it
			#chomp($pages[$#pages]);#chomp the copy instead of originally response data
			
			$pages{$x->{id}} = $x;#id->title
			chomp($pages{$x->{id}});
		}
		print "start: $start\nSize: $size\nlimit: $limit\n";#Prints the start #, size of previous return, and current limit size
		if ($getAll == 0){ last; }#if getAll flag is disabled it will stop after first pass
	}
	print "\n";
	return;
}