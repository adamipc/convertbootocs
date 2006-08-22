#!/usr/bin/perl -w
#
# Copyright (c) 2006 Adam Wendt <thelsdj@gmail.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# run with:
# find|grep -E "\.boo$"|xargs perl /path/to/ConvertBooToCs.pl
# (in the directory where there are .boo files to convert)

my $tabs = 0;
my $oldtabs = 0;

sub writetofile($$);
sub global_pre_process($);
sub line_by_line_process($);
sub global_post_process($); 
sub read_file($);

foreach my $file (@ARGV)
{
    my $contents = read_file($file);
    $contents = global_pre_process($contents);
    $contents = line_by_line_process($contents);
    $contents = global_post_process($contents);
    my $newfile = `dirname $file` . "/" . `basename $file .boo` . ".cs";
    $newfile = join("", split(/\n/, $newfile));
    print "Writing: " . $newfile . "\n";
    writetofile($newfile, $contents); 
};
exit;

sub writetofile($$)
{
    my $file = shift;
    my $contents = shift;
    open (FILE, "> $file");
    print FILE $contents;
    close (FILE);
}

sub global_pre_process($)
{
    $_ = shift;
    s/\x0D//g;
    s/\n\x20\x20\x20\x20/\n\t/sg;    
    
    # Merge joined lines.  Boo code example:
    #     elif CertificateValidation and \
    #        CertificateValidation(_client.Certificate, _client.CertificateErrors):
    #
    s/\\\n\s*/ /g;
    s/"""(.+?)"""/\/*$1*\//sg;
    return $_;
};

sub global_post_process($)
{
    $_ = shift;
    s/;\n(\s*)\{/\n$1\{/gs;
    s/\s*\n\s*\n\n*(\s*)\}/\n$1\}\n/gs;
    
    # Hacks to clean up parsing, probably better to fix earlier in the processing, but out of development time.
    s/namespace ([\w\.]+);(.*)/namespace $1\n{$2\n}/sg;
    s/import ([\w\. ]+);/using $1;/g;
    s/set\:\s*\n/set\n/g;
    
    # restore end of line comments.
    s/\n\#\!FIXLATER\!/\/\//g;

    @enums = split(/enum/, $_);
    for($i = 1; $i <= $#enums; $i++)
    {
        $enum = $enums[$i];
        if ($enum =~ /\s*(\w+)\s+\{(.+?)\}/s)
        {
            $name = $1;
            $stuff = $2;
            $stuff =~ s/\;/,/g;
            $enum =~ s/\s+\w+\s+\{.+?\}/ $name {$stuff}/s;
            print "ENUM MATCHED!\n";
            $enums[$i] = $enum;
        }
        else
        {
            print "ENUM DIDN'T MATCH?\n";
        }
    }

    $_ = join("enum", @enums);
    
    # Bad hack for previous bug
    s/public protected void /public void /g;
    s/public protected bool /public bool /g;
    
    # simple cleanup
    s/raise Exception/throw \(new Exception\(/g;

    return $_;
};

sub read_file($)
{
    my $file = shift;

    my $contents = "";
    open (FILE, $file);
    while (<FILE>)
    {
        $contents .= $_;
    };
    close (FILE);
    return $contents;
};

sub printtabs($)
{
    $count = shift;
    my $output = "";
    foreach (1..$count)
    {
        $output .= "\t";
    };
    return $output;
};

sub line_by_line_process($)
{
    my $contents = shift;
    my @lines = split(/\n/, $contents);
    my @newlines;
    foreach (@lines)
    {
        # Replace dedicated comment lines syntax from "#" to "\\"
        if (s/^(\s*)\#/$1\/\//)
        {
            push @newlines, $_;
            next;
        };

        # Quick rule for empty lines
        if (/^\s*$/)
        {
            push @newlines, "";
            next;
        };


        # take care of if statements.  they begin with "if " and end with ":" in boo.
        #  This will take care of both "if" and "elif" statements.
        if (s/if (.+?)\:/if \($1\)/g)
        {
            # ToDo:  These next two lines are actually global replace and not context specific to the $1 of the if match.
            s/\band\b/\&\&/g;
            s/\bnot\b/\!/g;
        };

        # replace "elif" with "elseif".
        s/elif \(/else if \(/g;
        
        # hack to fix broken if statements. Right now they are coming out with ";" after clause.
        s/if \((.+?)\)\s*;\s*\n/if \($1\)/g;
        
        # replace boo "except" with c# "catch" syntax.
        # Keep ":" on end so that ";" is not added to end of line.
        s/except (.+?)\:/catch \(Exception $1\):/g;
        
        # replace boo debug with C# Console.Writeline statements.
        s/^(\s*)debug\s+(.+)/$1Console.WriteLine($2)/;
        # replace boo print with C# Console.Writeline statements.
        s/^(\s*)print\s+(.+)/$1Console.WriteLine($2)/;

        # Replace "as (byte)" to just "as byte".  This appeared on a method parameter list.
        s/as \(byte\)/as byte[]/g;
        s/as\s*\(int\)/as int[]/g;


        # Replace indent blocks to explicit C# blocks {}
        $oldtabs = $tabs;
        $tabs = tabs($_); 
        if(/^\s+$/)
        {
            $_ = "";
        };

        while ($tabs > $oldtabs)
        {
            push @newlines, printtabs($oldtabs) . "{";
            $oldtabs++;
        };
        while ($oldtabs > $tabs)
        {
            push @newlines, printtabs($oldtabs-1) . "}";
            $oldtabs--;
        }


        # break end of line comments into next line comments.
        #   PROBLEM: it doesn't indent them properly and breaks blocks.
        unless (s/(\s*)\#/;$1\n\#\!FIXLATER\!/)
        {
            s/\Z/;/;
        };


        # Start of methods
        if (/\s*(.*?)\s*def (\w+)\((.*?)\)\s*(.*):?/)
        {
            my $stuff = $1;
            my $name = $2;
            my $params = $3;
            my $return = $4;
            print "RETURN: $return\n";
            my $newline = printtabs($tabs);
            
            if ($stuff)
            {
                $newline  .= "$stuff ";
            };

            if ($return =~ /\s*as\s+([\w\[\]]+)/)
            {
                $newline .= "$1";
            }
            else
            {
                $newline .= "void";
            };

            my @params = split(/,/,$params);
            my $newparams ="";
            foreach my $param (@params)
            {
                if ($param =~ /(\w+)\s+as\s+([\w\[\]]+)/)
                {
                    $newparams .= "$2 $1, ";
                }
                else
                {
                    $newparams .= "object $param, ";
                };
            };
            chop $newparams;
            chop $newparams;

            $newline .= " $name($newparams)";
            # if original line didn't end in :;, add ;
            unless ($_ =~ /:;\s*$/)
            {
                $newline .= ";";
            }
            else
            {
                if ($stuff ne "protected" || $stuff ne "private")
                {
                    $newline =~ s/^(\s*)/$1public /;
                } 
            }
            print "Converted:\n$_\nTo:\n$newline\n";
            $_ = $newline;
            
        }

        # Replace parameters structure of method start.
        # ToDo:  This needs to be inside the previous IF so it is only applied to structures intead of entire page.
        s/(\w+)\s+as\s+([\w\[\]]+)/$2 $1/g;

        # Fix :; at end of lines
        s/:;$//;

	# Fix ;; at end of lines
        s/;;\s*$/;/;

        # transform:
        # [getter(Session)]     _session = false;
        # to:
        # [getter(Session)] bool _session = false;
        s/^(\s*)(\S+)\s+(\w+)\s+=\s+(true|false)\s*;\s*$/$1$2 bool $3 = $4;/;

        $prop = 0;
        $get = 0;
        $set = 0;
        # [property(Priority)] _priority as int = 0
        if (/^(\s*)\[property\((\w+)\)\] (\w+) as ([\w\[\]]+) = (.+);/)
        {
            $prop = 1;
            $get = 1;
            $set = 1;
            $space = $1;
            $public = $2;
            $private = $3;
            $type = $4;
            $default = $5;
        }

        # [property(Details)] string details;
        if (/^(\s*)\[property\((\w+)\)\] ([\w\[\]]+) (\w+);/)
        {
            $prop = 1;
            $get = 1;
            $set = 1;
            $space = $1;
            $public = $2;
            $private = $4;
            $type = $3;
        }

        # transform:
        # [getter(Test)] string _test = "test";
        if (/^(\s*)\[getter\((\w+)\)\]\s+(\w+)\s+(\w+)\s+=\s+(.+);/)
        {
            $prop = 1;
            $space = $1;
            $public = $2;
            $type = $3;
            $private = $4;
            $default = $5;
            $get = 1;
        };

        if (/(\s*)\[prop\] (\w+) as ([\w\[\]]+)/)
        {
            $prop = 1;
            $space = $1;
            $public = $2;
            $type = $3;
            $private = "_" . lcfirst($public);
            $get = 1;
            $set = 1;
        }

        if (/(\s*)\[prop\] (\w+) (\w+) = (.*);?/)
        {
            $prop = 1;
            $get = 1;
            $set = 1;
            $space  = $1;
            $public = $3;
            $private = "_" . lcfirst($public);
            $type = $2
        }

        if ($prop)
        {
            $newline = "$space" .  "private $type $private";
            $newline .= " = $default" if $default;
            $newline .= ";\n";
            $newline .= "$space" . "public $type $public\n";
            $newline .= "$space\{\n";
            if ($get)
            {
                $newline .= "$space\tget\n";
                $newline .= "$space\t{\n";
                $newline .= "$space\t\treturn $private;\n";
                $newline .= "$space\t}\n";
            }
            if ($set)
            {
                $newline .= "$space\tset\n";
                $newline .= "$space\t{\n";
                $newline .= "$space\t\t$private = value;\n";
                $newline .= "$space\t}\n";
            }
            $newline .= "$space}";
            $_ = $newline;
        }

        # transform:
        # _dontRead = false;
        # to:
        # private bool _dontRead = false;
        # s/^(\s*)(\w+)\s+=\s+(true|false);/$1private bool $2 = $3;/;

        # translate:
        # class AsyncSynchronizer(ISynchronizer)
        # to:
        # class AsyncSyncronizer : ISynchronizer
        s/^(\s*)class\s+(\w+)\((\w+)\)/$1class $2 : $3/;

        # translate:
        # x = char('/');
        # to:
        # char x = '/';
        s/^(\s*)(\w+)\s+=\s+char\((.*?)\)/$1char $2 = $3/;

        # 'callable' means 'public delegate void' (unless theres a 'as foo' at end then its public delegate foo
        s/^(\s*)callable/$1public delegate void/;

        push @newlines, $_;
    }

    while ($tabs > 0)
    {
        push @newlines, printtabs($tabs-1) . "}";
        $tabs--;
    }

    $contents = join("\n", @newlines);
    return $contents;
};

sub tabs()
{
    my $line = shift;

    my $count = 0;
    if (/^(\t+)/)
    {
        $count = length($1);
    };
    return $count;
};
