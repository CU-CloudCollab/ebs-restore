# ebs-restore
Ruby script to find most recent EBS snapshot and restore to the instance.  This closes the AWS gaps identified in https://github.com/CU-CloudCollab/aws-gaps/issues/11 and https://github.com/CU-CloudCollab/aws-gaps/issues/12.

## Command Line Options
```
$ ./ebs_restore.rb -h
Usage: ebs_restore.rb [options]
    -r, --region region              AWS region (optional - will default to us-east-1) 
    -v, --volumeid volume-id         Volume ID (required) 
```

## Process

1. gather information about current volume
1. determine latest snapshot ID
1. create new volume
1. stop instance, if running, that the current volume is attached to
1. detach current volume from the instance
1. attach new volume to the instance
1. restart the instance
