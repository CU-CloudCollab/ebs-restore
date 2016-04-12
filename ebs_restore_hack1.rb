require 'aws-sdk'
require 'aws-sdk-resources'

require 'pry'

# export AWS_PROFILE=cu-training
# export AWS_REGION=us-east-1


ec2 = Aws::EC2::Resource.new

i = ec2.instances.select do |i|
  i.tags.any? do |t|
    t.key == 'Name' && t.value == 'Team5'
  end
end.first

volumes = i.volumes.entries

some_snapshots = volumes[1].snapshots.entries

sorted_some_snapshots = some_snapshots.sort_by(&:start_time).reverse


module Aws
  module EC2
    class Volume
      def attached_to?(instance)
        instance = to_instance(instance)
        instance.volumes.any? { |v| v.id == self.id }
      end
    end
  end
end



def restore_latest_snapshot(volume)
  volume = to_volume(volume)
  attachment = volume.attachments.select { |v| v.state == 'attached' }.first
  instance = Aws::EC2::Instance.new(attachment.instance_id)
  restore_latest_snapshot_to_instance(volume, instance, attachment.device)
end

def restore_latest_snapshot_to_instance(volume, instance, attachment_device=nil)
  volume = to_volume(volume)
  instance = to_instance(instance)

  if attachment_device.nil? && attachment = volume.attachments.select { |a| a.instance_id == instance.instance_id }.first
    attachment_device = attachment.device
  end
  raise "YO WHERE YOU WANT THIS" if attachment_device.nil?

  snapshot = volume.snapshots.sort_by(&:start_time).reverse.first
  raise "Y U NO HAVE SNAPSHOT" if snapshot.nil?

  instance_original_state = instance.state
  puts "stopping instance"
  stop_instance instance
  puts "instance stopped"

  # unmount existing volume, if it's mounted
  if volume.attached_to? instance
    puts "volume attached, so detaching"
    volume.detach_from_instance({ instance_id: instance.id })
  end
  puts "volume unattached"

  # create new volume from snapshot
  new_volume = create_and_wait_for_volume_from_snapshot(volume, snapshot)

  # mount new volume to instance
  new_volume.attach_to_instance({instance_id: instance.id, device: attachment_device})
  puts "attached to instance..."

  # return instance to remembered state
  if instance_original_state.name == "running"
    instance.start
  end

  new_volume
end

def stop_instance(instance)
  ## TODO: handle non "running"
  ## TODO: possibly add parameters to wait_until_stopped, or otherwise deal with it taking wayyyy long to stop
  instance = to_instance(instance)
  if instance.state.name == "running"
    instance.stop
    instance.wait_until_stopped
  elsif instance.state.name == "stopped"
    return
  else
    raise "not yet implemented: how to deal with #{instance.state.name}"
  end
end

def create_and_wait_for_volume_from_snapshot(volume, snapshot)
  puts "create_and_wait_for_volume_from_snapshot"
  volume = to_volume(volume)
  snapshot = to_snapshot(snapshot)

  params = {
    snapshot_id: snapshot.id,
    volume_type: volume.volume_type,
    availability_zone: volume.availability_zone,
  }
  if volume.volume_type == 'io1'
    params.update({ iops: volume.iops })
  end
  puts "about to create_volume"
  puts params
  resp = Aws::EC2::Resource.new.create_volume params
  new_volume = to_volume(resp.volume_id)

  puts "now waiting for new volume"
  new_volume.wait_until do |resource|
    resource.state =='available'
  end
  puts "got new volume"
  return new_volume
end

def to_instance(i)
  i.is_a?(String) ? Aws::EC2::Instance.new(i) : i
end

def to_volume(v)
  v.is_a?(String) ? Aws::EC2::Volume.new(v) : v
end

def to_snapshot(v)
  v.is_a?(String) ? Aws::EC2::Snapshot.new(v) : v
end

binding.pry
