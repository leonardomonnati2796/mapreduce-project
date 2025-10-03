# Test Multiple Input Files

## Files Created:
1. **data/Words.txt** - Original file about MapReduce framework
2. **data/Words2.txt** - New file about Apache Hadoop ecosystem
3. **data/Words3.txt** - New file about Machine Learning and AI

## Configuration Changes:
- Updated `docker/docker-compose.yml` to use: `/root/data/Words.txt,/root/data/Words2.txt,/root/data/Words3.txt`
- Updated `docker/docker-compose.aws.yml` with the same configuration

## Expected Behavior:
- The master should create **3 map tasks** (one for each input file)
- Each input file will be processed by a separate mapper
- The system should automatically adapt to use 3 mappers instead of 1
- All three files will be processed in parallel during the Map phase

## Content Summary:
- **Words.txt**: MapReduce framework concepts (4 lines, ~50 words)
- **Words2.txt**: Hadoop ecosystem tools (5 lines, ~60 words) 
- **Words3.txt**: Machine Learning and AI (6 lines, ~80 words)

## Total Processing:
- **Total lines**: 15 lines
- **Estimated words**: ~190 words
- **Map tasks**: 3 (one per file)
- **Reduce tasks**: 3 (default configuration)

## Verification Steps:
1. Start the cluster: `make start`
2. Check logs to verify 3 map tasks are created
3. Monitor dashboard to see 3 mappers processing
4. Verify output files contain words from all three input files
