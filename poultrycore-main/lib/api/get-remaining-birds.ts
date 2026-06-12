
import { supabase } from '@/integrations/supabase/client';

export const getRemainingBirds = async (batchId: string, farmId: string) => {
  if (!batchId || !farmId) {
    return 0;
  }

  const { data: batchData, error: batchError } = await supabase
    .from('flock_batches')
    .select('quantity')
    .eq('id', batchId)
    .single();

  if (batchError) {
    console.error('Error fetching batch quantity:', batchError);
    return 0;
  }

  const { data: flockData, error: flockError } = await supabase
    .from('flocks')
    .select('quantity')
    .eq('batch_id', batchId)
    .eq('farm_id', farmId);

  if (flockError) {
    console.error('Error fetching flock quantities:', flockError);
    return 0;
  }

  const totalFlockQuantity = flockData.reduce((acc, flock) => acc + flock.quantity, 0);
  const remainingBirds = batchData.quantity - totalFlockQuantity;

  return remainingBirds;
};
