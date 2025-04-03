# RUN: %fish %s

set -l oldpwd $PWD
cd (mktemp -d)
set tmpdir (pwd -P)

# Create mock history files for testing
set -g FISH_HISTORY_FILE "$tmpdir/fish_history"
set -g ZSH_HISTORY_FILE "$tmpdir/zsh_history"
set -g BASH_HISTORY_FILE "$tmpdir/bash_history"

# Create mock Fish history
echo "- cmd: ls -la
  when: 1617235678
- cmd: cd /home/user
  when: 1617235680
- cmd: git status
  when: 1617235685
- cmd: git add .
  when: 1617235690
- cmd: git commit -m \"Initial commit\"
  when: 1617235695
- cmd: git push origin main
  when: 1617235700
- cmd: npm install
  when: 1617235710
- cmd: npm start
  when: 1617235720
- cmd: git status
  when: 1617235730
- cmd: git pull
  when: 1617235740
- cmd: git push origin main
  when: 1617235750
- cmd: docker ps
  when: 1617235760
- cmd: docker-compose up -d
  when: 1617235770
- cmd: docker ps
  when: 1617235780
- cmd: ssh user@example.com
  when: 1617235790
- cmd: scp file.txt user@example.com:~/
  when: 1617235800
- cmd: ssh user@example.com
  when: 1617235810
- cmd: grep \"error\" /var/log/app.log
  when: 1617235820
- cmd: sudo systemctl restart nginx
  when: 1617235830
- cmd: git status
  when: 1617235840" > $FISH_HISTORY_FILE

# Create mock Zsh history 
echo ": 1617235680:0;cd /home/user
: 1617235690:0;git add .
: 1617235700:0;git push origin main
: 1617235720:0;npm start
: 1617235730:0;git status
: 1617235750:0;git push origin main
: 1617235760:0;docker ps
: 1617235780:0;docker ps
: 1617235800:0;scp file.txt user@example.com:~/
: 1617235820:0;grep \"error\" /var/log/app.log
: 1617235840:0;git status
: 1617235850:0;kubectl get pods
: 1617235860:0;kubectl describe pod web-app
: 1617235870:0;docker logs web-container" > $ZSH_HISTORY_FILE

# Create mock Bash history
echo "ls -la
cd /home/user
git status
git commit -m \"Another commit\"
git push origin develop
npm run build
docker ps -a
docker-compose down
ssh admin@server.com
systemctl status nginx
curl http://localhost:8080/api
git status
docker ps" > $BASH_HISTORY_FILE

# Source the hgrep function
# First, define a modified version for testing
function hgrep -d "Search command history with frequency and recency ranking across multiple shells"
    # Parse arguments
    set -l search_term ""
    set -l max_results 10
    set -l history_depth 1000
    set -l show_help 0
    set -l debug_mode 0
    set -l zsh_only 0
    
    # Process arguments
    set -l i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case '-h' '--help'
                set show_help 1
            case '-n' '--number'
                if test (count $argv) -gt $i
                    set i (math $i + 1)
                    set max_results $argv[$i]
                end
            case '-d' '--depth'
                if test (count $argv) -gt $i
                    set i (math $i + 1)
                    set history_depth $argv[$i]
                end
            case '--debug'
                set debug_mode 1
            case '--zsh-only'
                set zsh_only 1
            case '-*'
                echo "Unknown option: $argv[$i]" >&2
                set show_help 1
            case '*'
                set search_term $argv[$i]
        end
        set i (math $i + 1)
    end
    
    # Show usage if no search term provided or help requested
    if test $show_help -eq 1; or test -z "$search_term"
        echo "Usage: hgrep [options] <search_term>"
        echo ""
        echo "Options:"
        echo "  -h, --help              Show this help message"
        echo "  -n, --number NUMBER     Number of results to show (default: 10)"
        echo "  -d, --depth DEPTH       Number of history entries to search per shell (default: 1000)"
        echo "  --debug                 Show source shell for each command"
        echo "  --zsh-only              Only search zsh history"
        echo ""
        echo "Examples:"
        echo "  hgrep ssh               # Search for 'ssh' in history"
        echo "  hgrep -n 20 git         # Show top 20 'git' commands" 
        echo "  hgrep -d 1000 docker    # Search 1000 entries per shell for 'docker'"
        echo "  hgrep --zsh-only ssh    # Search only zsh history for 'ssh'"
        return 1
    end
    
    # Define history file paths for testing
    set -l zsh_history_file "$ZSH_HISTORY_FILE"
    set -l bash_history_file "$BASH_HISTORY_FILE"
    set -l fish_history_path "$FISH_HISTORY_FILE"
    
    # Current timestamp for establishing recency
    set -l current_time (date +%s)
    
    # Create arrays for history entries
    set -l history_commands
    set -l history_sources
    set -l history_timestamps
    
    # Get Fish history from the current session (limit by depth)
    # Skip if zsh-only mode is enabled
    if test $zsh_only -eq 0
        set -l fish_count 0
        for cmd in (_mock_history -n $history_depth | grep -i "$search_term")
            # Skip history and hgrep commands to avoid recursion
            if string match -q "*history*" -- "$cmd"; or string match -q "*hgrep*" -- "$cmd"
                continue
            end
            
            # Clean up the command (remove sudo prefix)
            set -l cleaned_cmd (string replace -r '^sudo ' '' -- "$cmd")
            
            # Skip empty lines
            if test -n "$cleaned_cmd"
                set -a history_commands $cleaned_cmd
                set -a history_sources "fish"
                
                # Assign decreasing timestamps based on position in fish history
                set -l timestamp (math "$current_time - $fish_count")
                set -a history_timestamps $timestamp
                set fish_count (math $fish_count + 1)
            end
        end
    end
    
    # Get Zsh history if the file exists (limit by depth)
    if test -e $zsh_history_file
        # Read Zsh history, extract timestamps and commands
        set -l zsh_lines (cat $zsh_history_file | tail -n $history_depth)
        for line in $zsh_lines
            # Extract and process command
            set -l cmd (string replace -r '^[^;]*;' '' -- "$line")
            
            # Only process if it matches search term
            if string match -q -i "*$search_term*" -- "$cmd"
                # Skip history and hgrep commands
                if string match -q "*history*" -- "$cmd"; or string match -q "*hgrep*" -- "$cmd"
                    continue
                end
                
                # Clean up the command (remove sudo prefix)
                set -l cleaned_cmd (string replace -r '^sudo ' '' -- "$cmd")
                
                # Skip empty lines
                if test -n "$cleaned_cmd"
                    # Extract timestamp if present (: timestamp:0;)
                    set -l timestamp 0
                    if string match -q -r '^: [0-9]+:[0-9]+;' -- "$line"
                        set timestamp (string replace -r '^: ([0-9]+):[0-9]+;.*' '$1' -- "$line")
                    end
                    
                    set -a history_commands $cleaned_cmd
                    set -a history_sources "zsh"
                    set -a history_timestamps $timestamp
                end
            end
        end
    end
    
    # Get Bash history if the file exists (limit by depth)
    # Skip if zsh-only mode is enabled
    if test $zsh_only -eq 0; and test -e $bash_history_file
        # Process bash history 
        set -l bash_count 0
        set -l bash_timestamp_base (math "$current_time - 1000000")  # Older than fish by default
        
        # Read bash history
        set -l bash_lines (cat $bash_history_file | tail -n $history_depth)
        for line in $bash_lines
            # Only process if it matches search term
            if string match -q -i "*$search_term*" -- "$line"
                # Skip history and hgrep commands
                if string match -q "*history*" -- "$line"; or string match -q "*hgrep*" -- "$line"
                    continue
                end
                
                # Clean up the command (remove sudo prefix)
                set -l cleaned_cmd (string replace -r '^sudo ' '' -- "$line")
                
                # Skip empty lines
                if test -n "$cleaned_cmd"
                    set -a history_commands $cleaned_cmd
                    set -a history_sources "bash"
                    
                    # Assign artificial timestamps for bash history
                    set -l timestamp (math "$bash_timestamp_base - $bash_count")
                    set -a history_timestamps $timestamp
                    set bash_count (math $bash_count + 1)
                end
            end
        end
    end
    
    # Check if we found any matches
    if test -z "$history_commands"
        echo "No matching commands found in history."
        return 0
    end
    
    # Debug step - print raw history entries
    if test $debug_mode -eq 1
        echo "DEBUG: Found" (count $history_commands) "history entries matching '$search_term'"
    end
    
    # Step 1: Create sorted indices by timestamp (most recent first)
    set -l all_indices (seq (count $history_commands))
    set -l timestamp_index_pairs
    
    for i in $all_indices
        set -a timestamp_index_pairs "$history_timestamps[$i]:$i"
    end
    
    # Sort the timestamp:index pairs by timestamp (descending)
    set -l sorted_pairs (printf '%s\n' $timestamp_index_pairs | sort -nr)
    
    # Extract the sorted indices
    set -l sorted_indices
    for pair in $sorted_pairs
        set -l parts (string split ":" -- "$pair")
        if test (count $parts) -ge 2
            set -a sorted_indices $parts[2]
        end
    end
    
    # Step 2: Build list of unique commands (preserving most recent occurrence)
    set -l unique_commands
    set -l unique_sources
    set -l unique_timestamps
    set -l seen_commands
    
    for idx in $sorted_indices
        set -l cmd $history_commands[$idx]
        if not contains -- "$cmd" $seen_commands
            set -a unique_commands $cmd
            set -a unique_sources $history_sources[$idx]
            set -a unique_timestamps $history_timestamps[$idx]
            set -a seen_commands $cmd
        end
    end
    
    # Debug step - print unique commands
    if test $debug_mode -eq 1
        echo "DEBUG: Found" (count $unique_commands) "unique commands"
    end
    
    # Step 3: Count frequencies for each unique command
    set -l command_counts
    
    for cmd in $unique_commands
        # Count how many times this command appears in the full history
        set -l count 0
        for hist_cmd in $history_commands
            if test "$hist_cmd" = "$cmd"
                set count (math $count + 1)
            end
        end
        set -a command_counts $count
    end
    
    # Step 4: Create source count structure for debug display
    set -l fish_counts
    set -l zsh_counts
    set -l bash_counts
    
    for cmd in $unique_commands
        # Initialize counts
        set -l fish_count 0
        set -l zsh_count 0
        set -l bash_count 0
        
        # Count by source
        for i in (seq (count $history_commands))
            if test "$history_commands[$i]" = "$cmd"
                switch $history_sources[$i]
                    case "fish"
                        set fish_count (math $fish_count + 1)
                    case "zsh"
                        set zsh_count (math $zsh_count + 1)
                    case "bash"
                        set bash_count (math $bash_count + 1)
                end
            end
        end
        
        set -a fish_counts $fish_count
        set -a zsh_counts $zsh_count
        set -a bash_counts $bash_count
    end
    
    # Step 5: Create indices for sorting by frequency
    set -l cmd_indices (seq (count $unique_commands))
    set -l freq_cmd_index_pairs
    
    for i in $cmd_indices
        set -a freq_cmd_index_pairs "$command_counts[$i]:$i"
    end
    
    # Sort by frequency (descending)
    set -l sorted_freq_pairs (printf '%s\n' $freq_cmd_index_pairs | sort -nr)
    
    # Extract the frequency-sorted indices
    set -l freq_sorted_indices
    for pair in $sorted_freq_pairs
        set -l parts (string split ":" -- "$pair")
        if test (count $parts) -ge 2
            set -a freq_sorted_indices $parts[2]
        end
    end
    
    # Limit to max_results
    if test (count $freq_sorted_indices) -gt $max_results
        set freq_sorted_indices $freq_sorted_indices[1..$max_results]
    end
    
    # Display header
    if test $debug_mode -eq 1
        echo "  # Total Fish  Zsh  Bash Recent  Command"
        echo "--- ----- ---- ---- ---- ------- -------"
    else
        echo "  #  Counts  Commands"
    end
    
    # For the test, we don't use colors to ensure consistent output
    # Display the results in frequency order
    set -l first_cmd_displayed 0
    set -l displayed_commands
    
    for i in (seq (count $freq_sorted_indices))
        set -l idx $freq_sorted_indices[$i]
        set -l cmd $unique_commands[$idx]
        set -l count $command_counts[$idx]
        set -l source $unique_sources[$idx]
        
        # Is this the first command?
        set -l is_first 0
        if test $first_cmd_displayed -eq 0
            set is_first 1
            set first_cmd_displayed 1
        end
        
        # Save command for potential recall
        set -a displayed_commands $cmd
        
        if test $debug_mode -eq 1
            # Debug mode - show detailed counts by shell
            printf "#%-2d " $i
            printf "%5s " $count
            printf "%4s " $fish_counts[$idx]
            printf "%4s " $zsh_counts[$idx]
            printf "%4s " $bash_counts[$idx]
            printf "%-7s " $source
            
            if test $is_first -eq 1
                echo -n "$cmd "
                echo "(Copied to clipboard!)"
            else
                echo "$cmd"
            end
        else
            # Standard mode
            printf "#%-2d " $i
            printf "%7s " $count
            
            if test $is_first -eq 1
                echo -n "$cmd "
                echo "(Copied to clipboard!)"
            else
                echo "$cmd"
            end
        end
    end
    
    # Copy the first command to clipboard
    if test (count $freq_sorted_indices) -ge 1
        set -l top_idx $freq_sorted_indices[1]
        echo -n $unique_commands[$top_idx] | _mock_clipboard_copy
    end
end

# Mock the history function
function _mock_history
    set -l depth 100
    if test (count $argv) -ge 2
        switch $argv[1]
            case '-n'
                set depth $argv[2]
        end
    end
    
    # Extract commands from our mock fish history
    grep -E "^- cmd: " $FISH_HISTORY_FILE | head -n $depth | sed 's/^- cmd: //'
end

# Mock the fish_clipboard_copy function
function _mock_clipboard_copy
    # Instead of copying to clipboard, store in a test file
    cat > "$tmpdir/clipboard_content"
end

# Source the actual function
source $oldpwd/share/functions/hgrep.fish

# Mock functions for testing
function history
    grep -E "^- cmd: " $FISH_HISTORY_FILE | sed 's/^- cmd: //'
end

function fish_clipboard_copy
    cat > "$tmpdir/clipboard_content"
end

# Run tests
echo "Test 1: Basic search for git"
hgrep git
# Run your tests...

# Clean up
cd $oldpwd
rm -Rf $tmpdir
