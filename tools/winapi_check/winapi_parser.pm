package winapi_parser;

use strict;

sub parse_c_file {
    my $options = shift;
    my $output = shift;
    my $file = shift;
    my $function_found_callback = shift;
    my $preprocessor_found_callback = shift;

    # global
    my $debug_channels = [];

    # local
    my $line_number = 0;
    my $documentation;
    my $linkage;
    my $return_type;
    my $calling_convention;
    my $function = "";
    my $argument_types;
    my $argument_names;
    my $argument_documentations;
    my $statements;

    my $function_begin = sub {
	$documentation = shift;
	$linkage = shift;
	$return_type= shift;
	$calling_convention = shift;
	$function = shift;
	$argument_types = shift;
	$argument_names = shift;
	$argument_documentations = shift;

	if($#$argument_names == -1) {
	    foreach my $n (0..$#$argument_types) {
		push @$argument_names, "";
	    }
	}

	if($#$argument_documentations == -1) {
	    foreach my $n (0..$#$argument_documentations) {
		push @$argument_documentations, "";
	    }
	}

	$statements = "";
    };
    my $function_end = sub {
	&$function_found_callback($line_number,$debug_channels,$documentation,$linkage,$return_type,
				  $calling_convention,$function,$argument_types,
				  $argument_names,$argument_documentations,$statements);
	$function = "";
    };
    my %regs_entrypoints;
    my @comments = ();
    my $level = 0;
    my $extern_c = 0;
    my $again = 0;
    my $lookahead = 0;
    my $lookahead_count = 0;

    print STDERR "Processing file '$file' ... " if $options->verbose;
    open(IN, "< $file") || die "<internal>: $file: $!\n";
    $/ = "\n";
    while($again || defined(my $line = <IN>)) {
	if(!$again) {
	    chomp $line;

	    if($lookahead) {
		$lookahead = 0;
		$_ .= "\n" . $line;
	    } else {
		$_ = $line;
		$lookahead_count = 0;
	    }
	    $lookahead_count++;
	    print " $level($lookahead_count): $line\n" if $options->debug >= 2;
	    print "*** $_\n" if $options->debug >= 3;
	} else {
	    $lookahead_count = 0;
	    $again = 0;
	}

	# Merge conflicts in file?
	if(/^(<<<<<<<|=======|>>>>>>>)/) {
	    $output->write("$file: merge conflicts in file\n");
	    last;
	}
      
	# remove C comments
	if(s/^(.*?)(\/\*.*?\*\/)(.*)$/$1 $3/s) { push @comments, $2; $again = 1; next }
	if(/^(.*?)\/\*/s) {
	    $lookahead = 1;
	    next;
	}

	# remove C++ comments
	while(s/^(.*?)\/\/.*?$/$1\n/s) { $again = 1 }
	if($again) { next; }

	# remove empty rows
	if(/^\s*$/) { next; }

	# remove preprocessor directives
	if(s/^\s*\#/\#/m) {
	    if(/^\\#.*?\\$/m) {
		$lookahead = 1;
		next;
	    } elsif(s/^\#\s*(.*?)(\s+(.*?))?\s*$//m) {
		if(defined($3)) {
		    &$preprocessor_found_callback($1, $3);
		} else {
		    &$preprocessor_found_callback($1, "");
		}
		next;
	    }
	}

	# Remove extern "C"
	if(s/^\s*extern\s+"C"\s+\{//m) { 
	    $extern_c = 1;
	    $again = 1;
	    next; 
	}

	my $documentation;
	my @argument_documentations = ();
	{
	    my $n = $#comments;
	    while($n >= 0 && ($comments[$n] !~ /^\/\*\*/ ||
			      $comments[$n] =~ /^\/\*\*+\/$/)) 
	    {
		$n--;
	    }

	    if(defined($comments[$n]) && $n >= 0) {
		$documentation = $comments[$n];
		for(my $m=$n+1; $m <= $#comments; $m++) {
		    if($comments[$m] =~ /^\/\*\*+\/$/ ||
		       $comments[$m] =~ /^\/\*\s*(?:\!)?defined/) # FIXME: Kludge
		    {
			@argument_documentations = ();
			next;
		    }
		    push @argument_documentations, $comments[$m];
		}
	    } else {
		$documentation = "";
	    }
	}

	if($level > 0)
	{
	    my $line = "";
	    while(/^[^\{\}]/) {
		s/^([^\{\}\'\"]*)//s;
		$line .= $1;
	        if(s/^\'//) {
		    $line .= "\'";
		    while(/^./ && !s/^\'//) {
			s/^([^\'\\]*)//s;
			$line .= $1;
			if(s/^\\//) {
			    $line .= "\\";
			    if(s/^(.)//s) {
				$line .= $1;
				if($1 eq "0") {
				    s/^(\d{0,3})//s;
				    $line .= $1;
				}
			    }
			}
		    }
		    $line .= "\'";
		} elsif(s/^\"//) {
		    $line .= "\"";
		    while(/^./ && !s/^\"//) {
			s/^([^\"\\]*)//s;
			$line .= $1;
			if(s/^\\//) {
			    $line .= "\\";
			    if(s/^(.)//s) {
				$line .= $1;
				if($1 eq "0") {
				    s/^(\d{0,3})//s;
				    $line .= $1;
				}
			    }
			}
		    }
		    $line .= "\"";
		}
	    }

	    if(s/^\{//) {
		$_ = $'; $again = 1;
		$line .= "{";
		print "+1: \{$_\n" if $options->debug >= 2;
		$level++;
	    } elsif(s/^\}//) {
		$_ = $'; $again = 1;
		$line .= "}" if $level > 1;
		print "-1: \}$_\n" if $options->debug >= 2; 
		$level--;
		if($level == -1 && $extern_c) {
		    $extern_c = 0;
		    $level = 0;
		}
	    }

	    if($line !~ /^\s*$/) {
		$statements .= "$line\n";
	    }

	    if($function && $level == 0) {
		&$function_end;
	    }
	    next;	    
	} elsif(/(extern\s+|static\s+)?((struct\s+|union\s+|enum\s+)?\w+((\s*\*)+\s*|\s+))
            ((__cdecl|__stdcall|CDECL|VFWAPIV|VFWAPI|WINAPIV|WINAPI|CALLBACK)\s+)?
	    (\w+(\(\w+\))?)\s*\(([^\)]*)\)\s*(\{|\;)/sx)
        {
	    $line_number = $. - $lookahead_count;

	    $_ = $'; $again = 1;
	    
	    if($11 eq "{")  {
		$level++;
	    }

	    my $linkage = $1;
	    my $return_type = $2;
	    my $calling_convention = $7;
	    my $name = $8;
	    my $arguments = $10;

	    if(!defined($linkage)) {
		$linkage = "";
	    }

	    if(!defined($calling_convention)) {
		$calling_convention = "";
	    }

	    $linkage =~ s/\s*$//;

	    $return_type =~ s/\s*$//;
	    $return_type =~ s/\s*\*\s*/*/g;
	    $return_type =~ s/(\*+)/ $1/g;

	    if($regs_entrypoints{$name}) {
		$name = $regs_entrypoints{$name};
	    } 

	    $arguments =~ y/\t\n/  /;
	    $arguments =~ s/^\s*(.*?)\s*$/$1/;
	    if($arguments eq "") { $arguments = "..." }

	    my @argument_types;
	    my @argument_names;
	    my @arguments = split(/,/, $arguments);
	    foreach my $n (0..$#arguments) {
		my $argument_type = "";
		my $argument_name = "";
		my $argument = $arguments[$n];
		$argument =~ s/^\s*(.*?)\s*$/$1/;
		# print "  " . ($n + 1) . ": '$argument'\n";
		$argument =~ s/^(IN OUT(?=\s)|IN(?=\s)|OUT(?=\s)|\s*)\s*//;
		$argument =~ s/^(const(?=\s)|CONST(?=\s)|\s*)\s*//;
		if($argument =~ /^\.\.\.$/) {
		    $argument_type = "...";
		    $argument_name = "...";
		} elsif($argument =~ /^
			((?:struct\s+|union\s+|enum\s+|(?:signed\s+|unsigned\s+)
			  (?:short\s+(?=int)|long\s+(?=int))?)?\w+)\s*
			((?:const)?\s*(?:\*\s*?)*)\s*
			(?:WINE_UNUSED\s+)?(\w*)\s*(?:\[\]|\s+OPTIONAL)?/x)
		{
		    $argument_type = "$1";
		    if($2 ne "") {
			$argument_type .= " $2";
		    }
		    $argument_name = $3;

		    $argument_type =~ s/\s*const\s*/ /;
		    $argument_type =~ s/^\s*(.*?)\s*$/$1/;

		    $argument_name =~ s/^\s*(.*?)\s*$/$1/;
		} else {
		    die "$file: $.: syntax error: '$argument'\n";
		}
		$argument_types[$n] = $argument_type;
		$argument_names[$n] = $argument_name;
		# print "  " . ($n + 1) . ": '" . $argument_types[$n] . "', '" . $argument_names[$n] . "'\n";
	    }
	    if($#argument_types == 0 && $argument_types[0] =~ /^void$/i) {
		$#argument_types = -1;
		$#argument_names = -1;  
	    }

	    if($options->debug) {
		print "$file: $return_type $calling_convention $name(" . join(",", @arguments) . ")\n";
	    }
	    
	    &$function_begin($documentation,$linkage,$return_type,$calling_convention,$name,\@argument_types,\@argument_names,\@argument_documentations);
	    if($level == 0) {
		&$function_end;
	    }
	} elsif(/__ASM_GLOBAL_FUNC\(\s*(.*?)\s*,/s) {
	    $_ = $'; $again = 1;
	    my @arguments = ();
	    &$function_begin($documentation, "", "void", "__asm", $1, \@arguments);
	    &$function_end;
	} elsif(/DC_(GET_X_Y|GET_VAL_16)\s*\(\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*\)/s) {
	    $_ = $'; $again = 1;
	    my @arguments = ("HDC16");
	    &$function_begin($documentation, "", $2, "WINAPI", $3, \@arguments);
	    &$function_end;
	} elsif(/DC_(GET_VAL)\s*\(\s*(.*?)\s*,\s*(.*?)\s*,.*?\)/s) {
	    $_ = $'; $again = 1;
	    my $return16 = $3 . "16";
	    my $return32 = $3;
	    my $name16 = $2 . "16";
	    my $name32 = $2;
	    my @arguments16 = ("HDC16");
	    my @arguments32 = ("HDC");

	    if($name16 eq "COLORREF16") { $name16 = "COLORREF"; }

	    &$function_begin($documentation, "", $name16, "WINAPI", $return16, \@arguments16);
	    &$function_end;
	    &$function_begin($documentation, "", $name32, "WINAPI", $return32, \@arguments32);
	    &$function_end;
	} elsif(/DC_(GET_VAL_EX)\s*\(\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*\)/s) {
	    $_ = $'; $again = 1;
	    my @arguments16 = ("HDC16", "LP" . $5 . "16");
	    my @arguments32 = ("HDC", "LP" . $5);
	    &$function_begin($documentation, "", "BOOL16", "WINAPI", $2 . "16", \@arguments16);
	    &$function_end;
	    &$function_begin($documentation, "", "BOOL", "WINAPI", $2, \@arguments32);
	    &$function_end;
	} elsif(/DC_(SET_MODE)\s*\(\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*\)/s) {
	    $_ = $'; $again = 1;
	    my @arguments16 = ("HDC16", "INT16");
	    my @arguments32 = ("HDC", "INT");
	    &$function_begin($documentation, "", "INT16", "WINAPI", $2 . "16", \@arguments16);
	    &$function_end;
	    &$function_begin($documentation, "", "INT", "WINAPI", $2, \@arguments32);
	    &$function_end;
	} elsif(/WAVEIN_SHORTCUT_0\s*\(\s*(.*?)\s*,\s*(.*?)\s*\)/s) {
	    $_ = $'; $again = 1;
	    my @arguments16 = ("HWAVEIN16");
	    my @arguments32 = ("HWAVEIN");
	    &$function_begin($documentation, "", "UINT16", "WINAPI", "waveIn" . $1 . "16", \@arguments16);
	    &$function_end;
	    &$function_begin($documentation, "", "UINT", "WINAPI", "waveIn" . $1, \@arguments32);
	    &$function_end;	    
	} elsif(/WAVEOUT_SHORTCUT_0\s*\(\s*(.*?)\s*,\s*(.*?)\s*\)/s) {
	    $_ = $'; $again = 1;
	    my @arguments16 = ("HWAVEOUT16");
	    my @arguments32 = ("HWAVEOUT");
	    &$function_begin($documentation, "", "UINT16", "WINAPI", "waveOut" . $1 . "16", \@arguments16);
	    &$function_end;
	    &$function_begin($documentation, "", "UINT", "WINAPI", "waveOut" . $1, \@arguments32);	    
	    &$function_end;
	} elsif(/WAVEOUT_SHORTCUT_(1|2)\s*\(\s*(.*?)\s*,\s*(.*?)\s*,\s*(.*?)\s*\)/s) {
	    $_ = $'; $again = 1;
	    if($1 eq "1") {
		my @arguments16 = ("HWAVEOUT16", $4);
		my @arguments32 = ("HWAVEOUT", $4);
		&$function_begin($documentation, "", "UINT16", "WINAPI", "waveOut" . $2 . "16", \@arguments16);
		&$function_end;
		&$function_begin($documentation, "", "UINT", "WINAPI", "waveOut" . $2, \@arguments32);
		&$function_end;
	    } elsif($1 eq 2) {
		my @arguments16 = ("UINT16", $4);
		my @arguments32 = ("UINT", $4);
		&$function_begin($documentation, "", "UINT16", "WINAPI", "waveOut". $2 . "16", \@arguments16);
		&$function_end;
		&$function_begin($documentation, "", "UINT", "WINAPI", "waveOut" . $2, \@arguments32);
		&$function_end;
	    }
        } elsif(/DEFINE_REGS_ENTRYPOINT_\d+\(\s*(\S*)\s*,\s*([^\s,\)]*).*?\)/s) {
	    $_ = $'; $again = 1;
	    $regs_entrypoints{$2} = $1;
	} elsif(/DEFAULT_DEBUG_CHANNEL\s*\((\S+)\)/s) {
	    $_ = $'; $again = 1;
	    unshift @$debug_channels, $1;
	} elsif(/(DEFAULT|DECLARE)_DEBUG_CHANNEL\s*\((\S+)\)/s) {
	    $_ = $'; $again = 1;
	    push @$debug_channels, $1;
	} elsif(/\'[^\']*\'/s) {
	    $_ = $'; $again = 1;
	} elsif(/\"[^\"]*\"/s) {
	    $_ = $'; $again = 1;
	} elsif(/;/s) {
	    $_ = $'; $again = 1;
	} elsif(/extern\s+"C"\s+{/s) {
	    $_ = $'; $again = 1;
        } elsif(/\{/s) {
            $_ = $'; $again = 1;
            print "+1: $_\n" if $options->debug >= 2;
            $level++;
        } else {
	    $lookahead = 1;
	}
    }
    close(IN);
    print STDERR "done\n" if $options->verbose;
    $output->write("$file: not at toplevel at end of file\n") unless $level == 0;
}

1;
