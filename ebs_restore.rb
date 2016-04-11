require 'aws-sdk'
require 'optparse'


# Options
# -r = region, -v volumeid
OPTIONS = {}

#Default Values
OPTIONS[:region] = 'us-east-1'

OptionParser.new do |opt|
  opt.on('--r REGION') { |o| OPTIONS[:region] = o }
  opt.on('--v VOLUMEID') { |o| OPTIONS[:volumeid] = o }
end.parse!

#set volume id
vol_id = OPTIONS[:volumeid]


ec2 = Aws::EC2::Client.new(:region=>OPTIONS[:region])

#get current volume parameters
curr_vol = ec2.describe_volumes({volume_ids: [vol_id]})
curr_instance_id = curr_vol.volumes[0].attachments[0].instance_id
curr_zone = curr_vol.volumes[0].availability_zone
curr_vol_type = curr_vol.volumes[0].volume_type
curr_device = curr_vol.volumes[0].attachments[0].device

puts "Volume #{vol_id} Properties:  "
puts "     Instance ID: " + curr_instance_id
puts "     Zone: " + curr_zone
puts "     Volume type: " + curr_vol_type
puts "     Device: " + curr_device



#get latest snapshot ID
snapshots_array = ec2.describe_snapshots({  filters: [{name: "volume-id",values: [vol_id],}]   })

puts ""
puts "All Snapshot IDs:"

snap_vals = []

snapshots_array.each do |a|
  a.snapshots.each do |b|
    snap_vals << {:snapshot_id => b.snapshot_id, :start_time => b.start_time}
    puts "\t #{b.snapshot_id} \t #{b.start_time}"
  end
end

snap_vals = snap_vals.sort_by { |v| v[:start_time] }.reverse
snap_id = snap_vals[0][:snapshot_id]

puts ""
puts "Most recent Snapshot ID: " + snap_id


#create a new volume
new_vol = ec2.create_volume({
              snapshot_id: snap_id,
              availability_zone: curr_zone,
              volume_type: curr_vol_type
          })

puts ""
puts "New Volume created with volume ID: " + new_vol.volume_id


#stop the instance, if needed
inst_status  = ec2.describe_instances({instance_ids: [curr_instance_id]})

if inst_status.reservations[0].instances[0].state.name == "running"
      ec2.stop_instances({ instance_ids: [curr_instance_id]})

      #wait until instance has stopped
      ec2.wait_until(:instance_stopped,instance_ids: [curr_instance_id])
end


#detach current volume
detach_vol = ec2.detach_volume({ volume_id: vol_id })
puts ""
puts "Old volume has been detached."

#attach new volume to instance that old volume is attached to
#check to make sure old volume is detached
ec2.wait_until(:volume_available,volume_ids: [vol_id])

#attach new volume
att_vol = ec2.attach_volume({
  volume_id: new_vol.volume_id,
  instance_id: curr_instance_id,
  device: curr_device
})

#start instance
ec2.start_instances({ instance_ids: [curr_instance_id]})

puts ""
puts "New volume has been attached and instance is restarting."
